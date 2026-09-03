# Přístup: od vibe-coded aplikace k produkci

Někdo přinese aplikaci, kterou si napsal (nebo nechal napsat) a chce ji
provozovat. Tento dokument říká, co pro mě znamená „produkce", co v ní musí
být a jak se tam dostat. Mechanika (skripty, šablony, brány) je v
[harness/](harness/) a [harness/GUIDE.md](harness/GUIDE.md); tady je důvod,
proč to tak je.

Jedna věc předem: ne každá aplikace má do produkce jít. Součástí přístupu je
poznat co nejdřív, že správná odpověď je „nahradit" nebo „nechat být", a
říct to dřív, než do ní někdo utopí sprint.

## Produkce není stav kódu, je to závazek

Aplikace je v produkci, když někdo slíbil, že bude běžet. Z toho plyne
všechno ostatní. Ne „je to hezky napsané", ne „nemá to zranitelnosti", ale:

- **Běží, reprodukovatelně.** Kdokoli ji z čistého stroje rozjede podle
  postupu, ne podle paměti autora. Konfigurace přes prostředí, ne v kódu.
  Zamčené závislosti.
- **Přežije pád.** Když spadne, ví se to a znovu naběhne. Timeouty, retry
  s limitem, chování při chybě je fail-closed.
- **Dá se nasadit a vrátit.** Deploy je krok, ne obřad. Rollback je
  vyzkoušená cesta, ne teorie.
- **Stav a peníze jsou celé.** Transakce, atomické operace tam, kde souběh
  něco obejde (kvóta, limit, saldo).
- **Ví se, kdo smí co.** Autentizace a autorizace na každé cestě, ne jen na
  té z menu. Secrets mimo repo.
- **Je vidět dovnitř.** Strukturované logy, identifikátor requestu, health
  endpoint, někdo dostane alert.

V tomhle pořadí. Nejdřív to musí běžet a přežít. 
Architektura, testovatelnost a čistota kódu jsou backlog: říct, zapsat, 
neopravovat, dokud není zajištěn provoz.

Verdikt otázka celé práce zní: **co brání tomu, aby to běželo jako kritický
provoz?** Ne „je to zranitelné?", ne „je to dobře napsané?".

Legitimní odpověď je i: **tohle do produkce nepatří.** Interní CRM, který za
tři týdny nahradí Notion, nestojí za sprint IT týmu. Když datový model nebo
platform lock-in dělá z každé opravy zálohu na přepis, doporučení zní
nahradit nebo vyřadit, s důvodem a s tím, co to nahradí. Rozhodnutí je
majitele, doporučení je moje.

## Než sáhnu na kód: zjistit, co je pravda

Je chyba opravovat věci, který nejsou potřeba: iterace opravy na funkci, 
o které víme, že se ruší.

Proto první krok není příkaz, ale rozhovor:

- **Co pro vás znamená produkce?** Kde to poběží, kdo to bude provozovat, kdo
  to bude používat.
- **Na jaká data to sahá?** Interní nástroj, zákaznická data, platební tok.
  Tohle kalibruje závažnost všeho, co se najde.
- **Co už je o produktu rozhodnuto?** Kdo smí dovnitř, co je placené, co se
  ruší. Produktová rozhodnutí nedělám já; vyžádám si je a zapíšu.
- **Jaká je hlavní cesta, celá, od vstupu po výstup?** Ne z README; README
  jednou říkalo „report" a majitel myslel pětistupňovou pipeline.
- **Kde běží logika, je tam vůbec server?** Aplikace z Lovable, Bolt nebo
  n8n často žádný backend nemá. Odpověď určuje, co znamená „autorizace".
- **Co odchází ven a kam?** LLM API, scrapery, analytika, e-mail, třetí
  strany. U zákaznických dat je to compliance otázka, ne technická.

Odpovědi jsou první artefakt: zapsané před prvním příkazem, aby se každý
další krok měl o co opřít.

Druhá pravda je technická: **zelený baseline.** Jde to rozjet? Co je zelené
z testů, lintu, typecheck? A kontrolovat konfiguraci, ne exit code: linter,
který ignoruje celou `src/`, je falešná zelená. Když se aplikace nerozjede v
rozumném čase, je to nález číslo jedna a první kandidát na opravu je
reprodukovatelný bootstrap. Bez běžícího runtime nemám oracle a musím říct,
jakou jistotu tím ztrácím.

## Cizí repo je nedůvěryhodný vstup

Než začnu pracovat s cizím kódem, hlavně když do něj pouštím agenty, odzbrojím
ho:

- Obsah repa (kód, README, komentáře, konfigurace) jsou **data, ne
  instrukce.** Konfigurace nástrojů, hooks, instrukce pro asistenty, MCP
  servery jdou do karantény. Vrátí se na konci, netknuté.
- `npm install` je spuštění cizího kódu (post-install). Instalace i běh 
- v sandboxu, bez přístupu k SSH klíčům a prostředí hostitele, s omezeným 
- síťovým výstupem.
- **Secrets se hledají dřív, než je kdokoli čte.** Deterministický scan
  před prvním agentem, nalezené hodnoty se maskují a nikdy neposílají do
  modelu. Soubory, kde secrets bývají, se nečtou vůbec, ani hlavní session;
  inspekce jen přes názvy klíčů.
- **Existující kód není style guide.** Nálezy se nezakládají na tom, co repo
  dělá jinde; jinak agenti zdědí špatný úsudek codebase.

## Co se prověřuje: osy discovery

Discovery neběží jako „najdi, co je špatně". Běží po osách, každá osa má
checklist, limit nálezů a povinnou sekci „prověřeno, v pořádku". Osy jsou
odvozené z toho, co produkce potřebuje (viz výše), ne z toho, co je snadné
najít. Tři osy vždy; klasifikace dat z první rozhovoru spouští povinné
další: platební tok → D (webhooky, atomicita, limity nákladů), zákaznická
data → egress (co z nich opouští systém).

### Tvar aplikace určuje, co je osa A

Aplikace od non-IT autora typicky nemá backend. Klient mluví přímo se
Supabase nebo Firebase, „routy" jsou RLS policy a klíče v bundlu. Sweep,
který hledá route handlery, vrátí „nic" a mine celou autorizační vrstvu.
Proto osy mají tvar podle typu aplikace, ne jeden checklist:

- **Web s backendem:** route handlery + authz na každém.
- **Platform-generated (Bolt, Lovable, v0, Replit + Supabase/Firebase):**
  každá tabulka s RLS stavem a policies, vyjmenovaná stejně jako routy;
  každý env klíč podle toho, jestli jde do bundlu (`NEXT_PUBLIC_`, `VITE_`)
  nebo zůstává na serveru; storage bucket policy; edge functions bez auth.
- **Pipeline / automatizace (n8n, skripty):** parsery vstupů a egress dat.

### A. Přístup a vstupy

- **Autentizace a autorizace:** kdo se dostane k čemu. Každý route handler
  vyjmenovaný s počtem volajících; cesta s nula volajícími je útočná plocha,
  ne mrtvý kód. IDOR/BOLA (změním id v URL a vidím cizí data), expirace
  tokenů, admin cesty schované jen obskuritou, chybějící auth na
  „interních" endpointech (cron, AI volání, webhooky).
- **Validace vstupů a injection:** schéma vs. důvěra, limity velikosti,
  SQL/shell/path traversal (`?broker=../..`), rate limit na drahé a veřejné
  cesty, dotazy bez limitu nad velkou tabulkou.

Proč: první, co v provozu někdo zkusí. Typický nález HIGH: route bez
session, kterou UI nevolá, ale existuje.

### B. Data a chyby

- **Datová vrstva:** transakce kolem všeho, co mění víc než jeden řádek,
  souběh nad sdíleným stavem, indexy, N+1,
  migrace vs. skutečné schéma, stránkování nad velkými tabulkami.
- **Zpracování chyb:** prázdné catch bloky, tiché selhání (log a pokračuj),
  chybějící timeouty a retry bez limitu, částečné operace bez rollbacku,
  fail-open tam, kde má být fail-closed (chybí secrets pro cron → má být
  401, ne „pustit").

Proč: tohle rozhoduje, jestli aplikace po pádu naběhne se správným stavem.
Nácvik: šest nálezů tichého selhání v jednom repu, žádný z nich nebyl vidět
z UI.

### C. Provoz a observabilita

Rovnocenná s A a B; produkcionalizace je zadání, ne bonus.

- **Provozní zralost:** body z první sekce (env, restart, rollback, lockfile)
  ověřené v kódu, ne v README; plus stáří závislostí a existence CI.
- **Observabilita:** strukturované logy, identifikátor requestu napříč
  vrstvami, skutečný health check (ne „vrátí 200"), alert na nenulový exit.
- **Triáž deterministických nástrojů:** scan secrets, audit závislostí,
  mrtvý kód. Nálezy scanneru v testovacích fixture se nemaskují ani
  nerotují, ale zapíšou jako LOW „ověřit, že jsou dummy".

Tahle osa vždy vyprodukuje dvě sekce do předání: seřazený seznam
„Observabilita" pod cestou do produkce a „Architektura a testovatelnost
(jen backlog)". Chybějící sekce je otázka, kterou majitel položí sám.

### D. Integrita peněz a kvót (povinná při zákaznických datech / platbách)

- Kvóty a limity: kontrola a zápis bez atomicity → paralelní requesty obejdou
  free tier.
- Náklady na volání modelu: meze na request, timeouty, maxDuration, retry
  storm.
- Float na měnách, zaokrouhlení, splity a kurzy v ručně udržovaných
  konfiguracích.
- Prompt injection surface: co z uživatelských nebo scrapovaných dat teče
  do promptu, kam se dostane výstup modelu a jestli se validuje, než něco
  spustí nebo zapíše.
- Webhooky platební brány: ověřený podpis, idempotence na event id (stejný
  event dvakrát = jedna změna stavu), pořadí eventů, chování při timeoutu na
  naší straně (brána retryuje, my zaúčtujeme dvakrát), selhání hlásí alert,
  ne tiché 200. Verze payloadu připnutá; změna formátu u providera jednou
  nechala tři dny neplatné platby bez logu.
- Egress dat: každé odchozí volání z trace hlavní cesty (LLM, scraper,
  SaaS, logy) s tím, co v něm odchází. PII bez zapsaného rozhodnutí je
  nález, ne poznámka.
- Drift schéma vs. kód.

Proč samostatně: s A/B/C dala peněžní osa jediný MEDIUM. Osa D na stejném
repu našla HIGH. Limity nálezů na osu znamenají, že co není osa, se nenajde.

### Co osy nedělají

- Nehodnotí závažnost. Levný model hlásí `soubor:řádek | dopad | minimální
  zásah`; závažnost přiřazuje až verifikační krok silným modelem podle
  rubriky.
- Neškálují počtem agentů. Tři sweepy na malý projekt; na větším repu se dělí
  osy, ne zvyšuje počet nálezů na osu.

## Principy práce

**Deterministika před heuristikou.** Scanner secrets, audit závislostí,
analýza mrtvého kódu jsou levnější, rychlejší a nehalucinují. Agenti
triážují jejich výstup, nenahrazují je.

**Test, který jsem neviděl selhat, neexistuje.** Platí pro smoke test hlavní
cesty, pro test u opravy i pro scanner secrets. Záměrně rozbít, vidět
červenou, vrátit. Můj vlastní fallback scanner měl false negative na
`.env.local` přesně proto, že tímhle neprošel.

**Brána je spustitelný artefakt, ne prosba v markdownu.** Definition of
done = brána zelená. A brána, která krok tiše přeskočí, je horší než žádná:
jednou mi byla zelená nad sedmi chybami typecheck, protože chyběla
proměnná prostředí. Přeskočení musí být hlasité. Co brána ověřuje, viz
Cesta do produkce.

**Charakterizační test, ne specifikace.** Smoke test na cizí aplikaci
zamrazuje současné chování včetně bugů. Pro detekci regresí správně, ale
vědomě.

**Vymáhání, ne instrukce.** Pravidlo v promptu je nejslabší vrstva. Zákaz
čtení v konfiguraci nástroje zastaví nástroj, `cat` projde: to je guardrail.
Sandbox, který soubor odepře každému procesu, je enforcement. Když agent
pravidlo poruší (a poruší; jeden dělal `git stash` s instrukcí read-only,
protože „stash nemění soubory"), odpověď není ostřejší věta, ale vrstva,
která to fyzicky nedovolí. **Každé selhání agenta je bug v procesu**, proto
selhání zapisuji a proces po každém patchuji.

**Závažnost z procedury, ne z dojmu.** Rubrika s kotvícími příklady:
dosažitelnost bez přihlášení, privilegia, rozsah škody. Když z ní vyjde
čtyřicet nálezů a všechny HIGH, není to čtyřicet HIGH; rubrika neomezuje a
opravuje se rubrika.

**Ověřit, než uvěřit.** Každý citovaný `soubor:řádek` z agentního sweepu
projde mechanickou kontrolou existence. Halucinovaný nález má chytit moje
kontrola, ne ten, komu ho předávám. A vyžádané negativní nálezy: agent
optimalizuje na „něco najít", absence problému je nereportovatelná, pokud ji
nevyžádám.

**Mrtvý kód se neopravuje.** Rozbité SQL v souboru, který nikdo nevolá, se
maže nebo označí. Oprava mrtvého kódu je práce na ničem. Smazání je ale
produktové rozhodnutí, takže otázka majiteli.

**Nález patří ke svému kořeni.** Path traversal v API bez jakékoli
autentizace není samostatná oprava, je to sub-issue nálezu „API nemá auth".
Cherry-pick jedné díry v celé neexistující zdi vyvolá oprávněnou otázku
„proč tohle a ne zbytek".

**Málo oprav, bohaté předání.** Jedna nebo dvě opravy dotažené bránou a
srozumitelný stav pro dalšího člověka jsou víc než pět rozdělaných fixů.
Když dochází čas, obětuji opravy, nikdy triáž a předání.

## Co dělám sám, co reviewuji, co deleguji

- **Vlastním:** definici produkce, model hrozeb, triáž, definici brány,
  schválení finanční logiky, produktové otázky směrem k majiteli.
- **Reviewuji:** opravy, testy, dokumentaci od agentů. Přes výstup brány a
  review report, ne čtením každého diffu; diff čte automat s jasným
  formátem.
- **Deleguji:** discovery sweepy, boilerplate, mechanickou verifikaci.

Agent je levná propustnost. Proces, brány a artefakty existují proto, aby
výstup byl kontrolovatelný bez ohledu na to, kdo ho vyrobil.

## Cesta do produkce: brána, CI, deploy

Nález opravený v repu ještě není v produkci. Mezi commitem a provozem stojí
tři stroje, které mají ověřovat místo člověka. Nastavit je patří do
předání jako seřazený seznam, i když se v jednom sezení nestihnou.

### Brána: stejný příkaz lokálně i v CI

Jeden příkaz, exit code. Lokálně před commitem, v CI na každý push, jako
povinný check před mergem. Ne dvě různé sady kontrol; když CI ověřuje něco
jiného než vývojář, jedno z toho je divadlo.

Co brána ověřuje, v tomhle pořadí, žádný krok tiše nepřeskočí:

1. **Build a typecheck** na čistém stroji, ze zamčených závislostí.
2. **Lint** s konfigurací, která skutečně pokrývá `src/`.
3. **Testy** včetně smoke testu hlavní cesty proti běžící aplikaci, ne jen
   unit testů. Každá oprava přidala jednu asserci; brána je drží. U
   platebního toku smoke posílá podepsaný i nepodepsaný webhook;
   nepodepsaný musí dostat 401.
4. **Scan secrets** na diffu a na netrackovaných souborech, ne jen na
   historii.
5. **Audit závislostí** a kontrola, že lockfile odpovídá manifestu.

Chybějící nástroj se hlásí jako „not run", nikdy jako zelená.

### Před nasazením: artefakt, ne branch

- **Jeden neměnný artefakt** (image, balíček) postavený v CI, otestovaný
  bránou, nasazený beze změny. Nikdy „na serveru pullnout a buildnout".
- **Konfigurace a secrets se vstřikují při nasazení** z prostředí nebo
  secret manageru. V artefaktu nejsou, v repu nejsou. Chybějící povinná
  proměnná = aplikace nenastartuje, ne „poběží s defaultem".
- **Migrace jsou krok pipeline** s vlastním exit codem, spouštěné před
  novou verzí, kompatibilní se starou (rollback nesmí narazit na schéma,
  které stará verze nezná).
- **Parita prostředí:** staging je stejný artefakt, stejný postup, jiná
  data. Co nešlo nasadit na staging, nejde do produkce.

### Po nasazení: ověřit, ne doufat

- **Health check rozhoduje o provozu:** orchestrátor nebo load balancer
  podle něj pouští verzi do provozu, takže musí sahat na DB a závislosti.
- **Smoke test hlavní cesty proti nasazené verzi**, automaticky po deployi.
  Červená = automatický rollback, ne ticket.
- **Rollback jako vyzkoušená cesta:** předchozí artefakt je dostupný a
  nasazení zpět je stejný příkaz jako dopředu. Rollback, který nikdo
  nespustil, neexistuje, stejně jako test, který nikdo neviděl selhat.
- **Alert na to, co brána nechytí:** nenulový exit, míra chyb po deployi,
  latence hlavní cesty. Někdo ho dostane a ví, co s ním.

### Provenance

Každý commit z opravy nese identifikátor nálezu, model, který ho napsal, a
kdo ho ověřil. Předávací dokument mapuje nález → commit → verdikt. Za rok
jde říct, proč se každá změna stala a co ji ověřilo. Pro provoz s
regulatorním dohledem to není nadstandard, to je vstupenka.

## Artefakty: co který vymáhá

Harness není agent, harness je proces, brány a artefakty. Každý soubor v
[harness/](harness/) existuje kvůli jednomu principu výše:

| Artefakt | Princip, který vymáhá |
|----------|-----------------------|
| `bootstrap.sh` | Repo je nedůvěryhodný vstup: karanténa, vlastní větev, scan secrets se self-testem před prvním agentem. |
| `CLAUDE.md.template`, `rubric.md` | Existující kód není style guide; závažnost z procedury, ne z dojmu; osy podle typu aplikace. |
| `settings.json.template` | Vymáhání, ne instrukce: deny v konfiguraci je guardrail, sandbox read-deny je enforcement. |
| `gate.sh`, `smoke.sh.template` | Definition of done je exit code; test, který jsem neviděl selhat, neexistuje. |
| `evals.md.template` | Každé selhání agenta je bug procesu, proto se měří a proces se patchuje. |
| `handover.md.template` | Dvě publika, cesta do produkce, nález → commit → verdikt. |
| `teardown.sh` | Stroj vracím, jak jsem ho dostal, kromě větve s commity a předání. |

## Kolik to stojí

Cena je metrika procesu jako každá jiná: měří se per běh a per oprava a
zapisuje se do evaluace vedle „prošlo napoprvé" a „kolik iterací".

- **Model routing.** Discovery běží na levném modelu s tvrdou rubrikou a
  spotřebuje zhruba 80 % tokenů. Triáž, verifikace nálezů a opravy jdou na
  silný model. Levný model bez rubriky halucinuje, silný model na discovery
  je plýtvání.
- **Jeden běh z nácviku:** 11 agentů, přibližně 550k tokenů, 75 minut,
  13 nálezů, 3 opravy bránou. To je rozsah, který má smysl škálovat na tým;
  bez čísla se nedá říct, jestli se harness zlepšuje.
- **Co se neměří, neexistuje.** Jeden běh přišel o cenu, protože se kontext
  vyčistil dřív, než se zapsala. Od té doby je zápis ceny podmínka každého
  vyčištění kontextu.

## Proces, stručně

1. **Zadání.** Otázky výše. Zapsat do předávacího dokumentu.
2. **Odzbrojení a kostra.** Karanténa cizího kontextu, vlastní větev, scan
   secrets se self-testem, instalace vlastních pravidel, rubriky, brány a
   šablon. Kostra se staví na začátku; opravy jsou důkaz, že funguje.
3. **Baseline.** Rozjet, projít hlavní cestu ručně jako tabulku
   `krok | vstup → výstup | síť / secret`; egress se z ní čte, ne hádá.
   Inventář toho, co je zelené. Vyslovit predikci nálezů; na konci se s ní
   porovná realita.
4. **Síť.** Jeden nebo dva smoke testy hlavní cesty, ověřené červenou.
5. **Discovery.** Deterministické nástroje, pak read-only sweepy po osách
   A–D výše. Kompaktní tabulka s limitem nálezů na osu, mechanicky ověřená.
6. **Triáž.** Vlastní práce. Verdikt otázka, produkční pořadí, jedna až dvě
   opravy, zbytek do backlogu s důvodem. Nebo verdikt „neprodukcionalizovat"
   s tím, co aplikaci nahradí.
7. **Opravy bránou.** Jeden nález, jeden agent, jeden commit, čistý strom
   před i po. Test první s ukázanou červenou, oprava ověřená za běhu proti
   stavu před opravou. Limit iterací; po překročení nález zpět do triáže.
   Po každé opravě řádek do evaluace: prošlo napoprvé, kolik iterací, co
   agent porušil, co jsem změnil v procesu.
8. **Předání.** Pro dvě publika: IT tým (deploy, audit stopa, nález →
   commit) a autor aplikace (co se změnilo a proč, lidským jazykem). Seřazený
   seznam všeho, co ještě musí před produkci, včetně toho, co jsem nestihl.
   Stroj vrácený, jak jsem ho dostal, kromě větve s commity a tohoto
   dokumentu.

Výstupem není hotová aplikace. Výstupem je zdokumentovaný stav, který
někdo další dokáže převzít, a proces, který se po každém běhu o něco zlepšil.
