# MacFlow redesign system

## Product character

MacFlow is a native macOS control workspace, not a web dashboard and not a collection of independent settings panes. Every screen uses the same graphite shell, density, interaction model, typography hierarchy, and state language. Module color identifies context but never becomes the page background.

The visual priorities are:

1. Readable hierarchy before decoration.
2. Direct manipulation before explanatory cards.
3. Dense, aligned information without crowding.
4. Native macOS controls where their behavior is familiar.
5. One restrained blue product accent, with quiet module accents.

## Global app shell

The companion window uses one persistent shell:

```text
[ 224 pt navigation ] [ flexible content canvas ] [ optional 280–320 pt inspector ]
```

- Minimum window: `1080 × 700 pt`.
- Ideal window: `1240 × 780 pt`.
- Sidebar stays visible at all supported sizes.
- The main canvas owns the page toolbar and scroll position.
- The inspector appears only when the selected module has a selected object or advanced context. It is not an empty decorative column.
- No global marketing hero is repeated on internal module pages.
- The titlebar is visually merged with the shell but retains native traffic-light behavior.

### Sidebar

- 224 pt fixed width.
- Brand row: 40 pt icon, MacFlow name, short product status.
- Primary navigation: Home, Notch, MouseFree, Wallpapers.
- Utility navigation: Preferences, About MacFlow.
- Selected item: neutral raised fill, 1 px blue leading indicator, blue icon only.
- Hover: neutral fill only; no scaling.
- Bottom runtime summary shows actual enabled module count and one useful status line.
- Module colors do not recolor the entire row.

### Page toolbar

- 68 pt default height, 76 pt only when a secondary line is necessary.
- Left: eyebrow, page title, optional concise subtitle.
- Right: page-specific primary actions, compact search/filter controls, or a master toggle.
- No duplicated global module-status icons on every page.
- Toolbar actions remain stable while the page scrolls.

## Layout and spacing scale

All measurements derive from the following scale:

| Token | Value | Use |
| --- | ---: | --- |
| `space2` | 2 pt | optical label adjustment |
| `space4` | 4 pt | title/subtitle pairs |
| `space6` | 6 pt | compact icon/text pairs |
| `space8` | 8 pt | control groups |
| `space12` | 12 pt | row internals, grid gap |
| `space16` | 16 pt | standard panel padding |
| `space20` | 20 pt | section separation |
| `space24` | 24 pt | canvas inset |
| `space32` | 32 pt | major page regions |

- Settings rows: 54–62 pt, depending on subtitle.
- Compact cards: 12–16 pt internal padding.
- Preview panels: 18–20 pt padding.
- Large blank gaps above 32 pt require a semantic reason.
- Content aligns to a common 24 pt page grid.

## Color system

### Neutral layers

- `appBackground`: `#0C0D10` — window behind the shell.
- `sidebar`: `#111318` at 96% — navigation plane.
- `canvas`: `#0F1115` — main content.
- `surface1`: white at 3.5% over canvas — grouped rows and controls.
- `surface2`: white at 5.5% — selected or elevated content.
- `surface3`: white at 7.5% — hover and active control surfaces.
- `borderSubtle`: white at 7%.
- `borderStrong`: white at 12%.
- `textPrimary`: native label color.
- `textSecondary`: native secondary label at 88%.
- `textTertiary`: native tertiary label.

The app follows the active appearance, but its authored presentation is dark-first. Light mode may use native adaptive surfaces without introducing saturated page backgrounds.

### Accent strategy

- Product action: calm system blue (`#4D8DFF`).
- Notch identity: blue-cyan, icon/selection only.
- MouseFree identity: warm amber, chart and selected preset only.
- Wallpapers identity: muted indigo-violet, selection and apply action only.
- Success: system green.
- Warning: system orange.
- Destructive: system red.

Only one module accent is visible as a dominant accent inside a module page. Home may show all three only as tiny identity markers.

## Typography

All text uses SF Pro through system fonts.

| Role | Style |
| --- | --- |
| Page title | 26 pt semibold, rounded only for Home headline |
| Module title | 22 pt semibold |
| Section title | 12 pt semibold, uppercase, 0.8 tracking |
| Panel title | 14 pt semibold |
| Row title | 13 pt medium |
| Body | 12–13 pt regular |
| Secondary | 11–12 pt regular |
| Metadata | 10 pt medium/monospaced where numeric |

- Internal utility screens avoid 32+ pt marketing type.
- Labels never rely on color alone.
- Numeric values use monospaced digits.

## Radius, border, and depth

- Window/shell: 22 pt.
- Large preview: 18 pt.
- Standard panel: 14 pt.
- Compact control/card: 10 pt.
- Button: native bordered radius or 8–10 pt custom radius.
- Capsule is reserved for status, filter chips, and segmented states.

One surface draws one border. Shadows are used only for the shell, menus, selected wallpaper preview, and transient overlays. Standard setting rows do not cast shadows.

## Shared component catalog

### `MacFlowPageHeader`

- Eyebrow, title, optional subtitle.
- Slots for primary and secondary actions.
- Optional master toggle with an explicit label.
- Compact and regular variants.

### `MacFlowSectionHeader`

- Uppercase label on the left.
- Optional explanatory text or trailing action.
- Never placed inside a redundant card header.

### `MacFlowPanel`

Variants:

- `plain`: only alignment and optional separator.
- `grouped`: `surface1` with subtle border.
- `elevated`: `surface2`, used for previews and active selections.
- `inspector`: denser grouped surface with 12 pt padding.

### `MacFlowSettingsGroup` and `MacFlowSettingsRow`

- Contiguous rows inside one grouped surface.
- Leading 30–34 pt symbol tile is optional.
- Title and subtitle align across all rows.
- Trailing content supports toggle, menu, value, disclosure, and action.
- Dividers start at the text column, not the outer panel edge.

### Buttons

- `primary`: system blue filled, used once per page region.
- `secondary`: neutral bordered.
- `quiet`: label/icon with hover surface.
- `destructive`: red only for Stop, Delete, Clear, or Remove.
- Icon-only controls are 28–32 pt with accessibility labels and tooltips.

### Tabs and segmented controls

- Native segmented picker for 2–4 global choices.
- Custom underline/tab strip for 5+ module subsections.
- Selected state uses a neutral fill plus a thin module accent marker.
- Tabs never sit inside an unrelated large card.

### Inspector

- 280–320 pt width.
- Sticky selected-item header.
- Detail, Settings, and Displays tabs only when those tabs contain real content.
- Controls use compact rows and grouped subsections.
- Empty selection collapses the inspector rather than showing a large empty card.

### Charts

- One hairline baseline and no more than three horizontal guides.
- Secondary axis labels at 10 pt.
- 2 pt accent curve with a restrained 8–12% area fill.
- Chart background is the main panel; no extra nested rounded rectangle.
- Reduce Motion disables animated curve interpolation.

### Empty, loading, and error states

- Empty state occupies the content region, not a tiny unrelated card.
- Contains one symbol, one title, one sentence, and one primary action.
- Loading uses a static skeleton under Reduce Motion and a subtle shimmer otherwise.
- Errors use inline recovery panels and preserve surrounding content.

## Screen templates

### Home — command center

- Compact command header, not a marketing landing page.
- Module launch strip with three equal, information-dense modules.
- Runtime table with real status, current selection/profile, and direct action.
- Recent activity uses actual state only; no fabricated metrics.

### Notch — configuration workspace

- Module header with master toggle and hardware preview.
- Persistent subsection tab strip.
- Overview summarizes runtime, enabled capabilities, and quick configuration.
- Detailed tabs reuse grouped rows and progressive disclosure.
- Notch shape preview is functional context, not decoration.

### MouseFree — tuning studio

- Compact status/permission row.
- Response chart is the main work area.
- Presets are a one-line selectable strip.
- Fine tuning uses aligned label, slider, and numeric value columns.
- Behavior toggles occupy a dense settings group below the tuning tools.

### Wallpapers — scene manager

- Dedicated browser toolbar with search, kind filter, sort, grid/list control, and Import.
- Active/selected scene preview spans the primary canvas width.
- Scene library is a dense adaptive grid.
- Selecting a scene opens a real right inspector.
- Collections and automation are secondary browser controls, not full-width dashboard cards.
- Scene thumbnails use actual local preview data; no invented art.

### Preferences — app-level settings

- Calm grouped form with General, Appearance, Updates, and Onboarding sections.
- No module-specific controls.
- No hero or module accent.

### About — product information

- Centered brand block balanced by a compact information panel.
- App icon, name, tagline, version/build, update action, license, and credits.
- Avoids a mostly empty canvas.

## Interaction states

- Hover: 120 ms ease-out, neutral surface increase only.
- Pressed: 0.98 scale only for discrete cards/buttons; no list-row scaling.
- Selection: 180–220 ms damped spring, no bounce.
- Page transition: 180 ms crossfade with 6 pt horizontal movement; Reduce Motion uses opacity only.
- Disabled: 45% content opacity with no hover response.
- Loading: controls remain spatially stable.
- Focus: native keyboard focus ring remains visible.

## Accessibility rules

- Every icon-only button has a label and help text.
- Status includes text, not only a colored dot.
- Minimum interactive target: 28 × 28 pt on macOS.
- Full keyboard traversal follows visual order.
- Increase Contrast raises border opacity and removes translucent text.
- Reduce Transparency uses opaque graphite surfaces.
- Reduce Motion removes scale, offset, shimmer, and chart interpolation.
- Dynamic Type is not available on macOS in the iOS sense, so layouts must tolerate accessibility display scaling and longer localization strings.
