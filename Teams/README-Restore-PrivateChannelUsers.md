# Restore-PrivateChannelUsers.ps1

Krátký návod ke skriptu pro obnovu členů v privátních kanálech Microsoft Teams.

## Co skript dělá

- Prochází vybrané týmy (jeden tým, více týmů z CSV, nebo všechny týmy).
- Najde privátní kanály podle klíčových slov v názvu (výchozí: audit, pbc).
- Do kanálů přidá uživatele z member CSV jen pokud jsou zároveň členy daného M365 týmu.
- Ownery kanálu nastaví z owner CSV, ale jen pokud jsou ownerem daného M365 týmu.
- Pokud je někdo v member seznamu a je owner týmu, je v kanálu veden jako Owner (ne Member).
- Pokud není dostupný vhodný owner z owner CSV, použije se fallback owner.
- Umí volitelně zajistit členství uživatelů i na úrovni týmu před přidáním do privátních kanálů.

## Předpoklady

- Nainstalovaný PowerShell modul MicrosoftTeams.
- Oprávnění pro práci s týmy/kanály.
- Přihlášená relace do Teams, nebo povolit připojení skriptem.

## Vstupní soubory

### Members CSV

Soubor pro members musí obsahovat aspoň jeden sloupec:
- UserPrincipalName
- UPN
- User

Příklad:
UserPrincipalName
jan.novak@firma.cz
petra.svobodova@firma.cz

### Owners CSV

Stejný formát jako members CSV (sloupce UserPrincipalName nebo UPN nebo User).

### Teams CSV

Podporované formáty:

1) Jednoduchý seznam týmů po řádcích (bez hlavičky):
HOME
Park Holiday
HMG

2) CSV s hlavičkou (pro jednoznačný výběr podle TeamId):
TeamId,TeamName
aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee,Park Holiday

Pokud je podle TeamName nalezeno více týmů, skript vypíše kandidáty a vyžádá TeamId interaktivně.

## Nejčastější spuštění

Spuštění nad více týmy ze souboru teams:

./Restore-PrivateChannelUsers.ps1 -TeamsCsvPath "./Restore-PrivateChannelUsers-teams.csv" -OwnersCsvPath "./private-channel-owners.csv" -UsersCsvPath "./private-channel-members.csv" -EnsureTeamMembership -SkipConnect

Spuštění jen nad jedním týmem:

./Restore-PrivateChannelUsers.ps1 -TeamName "Název týmu" -OwnersCsvPath "./private-channel-owners.csv" -UsersCsvPath "./private-channel-members.csv" -EnsureTeamMembership -SkipConnect

## Parametry

- TeamId
  - ID jednoho konkrétního týmu.
  - Nelze kombinovat s TeamName a TeamsCsvPath.

- TeamName
  - Název jednoho týmu.
  - Match je case-sensitive (rozlišuje velká/malá písmena).
  - Nelze kombinovat s TeamId a TeamsCsvPath.

- TeamsCsvPath
  - Cesta k CSV se seznamem týmů.
  - Nelze kombinovat s TeamId/TeamName.

- ChannelName
  - Volitelný filtr názvu kanálu (další omezení nad klíčová slova).

- AllowedChannelKeywords
  - Klíčová slova pro výběr privátních kanálů podle názvu.
  - Výchozí hodnoty: audit, pbc.

- MemberUpns
  - Volitelný inline seznam member UPN.
  - Alternativa k UsersCsvPath.

- UsersCsvPath
  - Cesta k members CSV.

- OwnerUpns
  - Volitelný inline seznam owner UPN.
  - Alternativa k OwnersCsvPath.

- OwnersCsvPath
  - Cesta k owners CSV.

- FallbackOwnerUpn
  - Owner použitý, když v týmu není žádný vhodný owner z owner vstupu.
  - Výchozí: milan.nemec@grinex.cz.

- EnsureTeamMembership
  - Pokud je zapnuto, skript před přidáním do privátního kanálu nejdřív zajistí členství v týmu.

- SkipConnect
  - Pokud je zapnuto, skript nepouští Connect-MicrosoftTeams a používá aktuální relaci.

## Poznámky

- Skript vypisuje průběžný stav s časem od startu.
- Změny provádí postupně po týmech.
- U transient chyb má krátké retry.
