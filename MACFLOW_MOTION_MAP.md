# MacFlow Motion Map

Motion v MacFlow vysvětluje změnu stavu nebo zachovává kontext. Stabilní navigace,
pozadí a dlouhé seznamy se neanimují.

| Interakce | Účel | Animované vlastnosti | Délka | Křivka | Reduce Motion alternativa |
| --------- | ---- | -------------------- | ----- | ------ | ------------------------- |
| Zobrazení/skrytí sidebaru | Zachovat navigační kontext | nativní šířka sloupce | 220 ms | ease-in-out | okamžitá změna |
| Změna hlavní sekce | Potvrdit nový kontext | opacity | 160 ms | ease-out | 100ms crossfade |
| Změna onboarding kroku | Vysvětlit postup vpřed/zpět | opacity, posun 8 pt | 220 ms | ease-out | crossfade |
| Onboarding progress | Zachovat polohu v průvodci | šířka indikátoru | 220 ms | jemná spring | okamžitá změna barvy |
| Aktivace wallpaperu | Potvrdit výběr a aplikaci | selection stroke, status symbol | 160 ms | jemná spring | barva + symbol bez scale |
| Změna aktivního preview | Zachovat vazbu dlaždice → preview | opacity | 220 ms | ease-in-out | 100ms crossfade |
| Změna velikosti notch preview | Ukázat skutečný dopad nastavení | šířka, výška a shape path | 340 ms | kontrolovaná spring | okamžitá geometrie + crossfade obsahu |
| Udělení oprávnění | Potvrdit dokončení akce | opacity, symbol replacement | 160 ms | ease-out | okamžitá změna symbolu |
| Import wallpaperu | Zachovat strukturu během práce | systémový progress + statická strukturální kostra | systémová | systémová | stejná statická kostra |
| Chyba importu | Upozornit bez narušení layoutu | systémový alert | systémová | systémová | beze změny |

## 1. Systémové transitions

- Sidebar používá nativní `NavigationSplitView`; animuje se pouze změna viditelnosti sloupce.
- Obsah sekcí používá krátký crossfade. Navigace a toolbar zůstávají stabilní.
- Onboarding používá jeden dominantní přechod obsahu; footer a notch shell zůstávají na místě.

## 2. Microinteractions

- Aktivace wallpaperu mění stav dlaždice a status symbol bez pohybu okolního gridu.
- Primární onboarding akce používají systémový pressed stav a existující haptickou odezvu.
- Permission stav přechází z akce na potvrzení bez změny výšky řádku.

## 3. Shared-element transitions

- Onboarding progress používá jeden sdílený indikátor mezi kroky.
- Wallpaper grid nepřenáší celý obrázek do preview pomocí scale; velký bitmapový shared-element
  by zbytečně zatěžoval render. Preview proto používá levnější crossfade.

## 4. Loading a progress

- Import používá statickou strukturální kostru a systémový `ProgressView`.
- Neurčité operace nepřidávají vlastní nekonečný spinner.

## 5. Stavové a potvrzovací animace

- Stav aktivního wallpaperu, permission success a notch content size používají explicitní změny stavu.
- Žádná animace není řízená nekonečným časovačem ani globální `.animation` na celé obrazovce.
