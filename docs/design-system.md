# SMARTIFY — Design System Specification

SMARTIFY uses an **Academic Slate & Deep Emerald** design system engineered specifically for an Android-first campus experience. It avoids generic white templates with a single accent, providing distinct, high-contrast, multi-token palettes that support both light and dark modes in compliance with WCAG 2.2 AA.

---

## 1. Semantic Color Tokens

### A. Brand & Hierarchy Tokens

| Token Name | Light Mode (HEX) | Dark Mode (HEX) | Purpose |
| :--- | :--- | :--- | :--- |
| `colorBrandPrimary` | `#0D9488` (Teal 600) | `#14B8A6` (Teal 500) | Primary actions, branding, active headers |
| `colorOnBrandPrimary` | `#FFFFFF` | `#042F2E` (Teal 950) | High-contrast text on primary |
| `colorPrimaryContainer` | `#CCFBF1` (Teal 100) | `#134E4A` (Teal 900) | Subdued card accents, highlighted pills |
| `colorOnPrimaryContainer` | `#115E59` (Teal 800) | `#5EEAD4` (Teal 300) | Text on primary containers |
| `colorBrandSecondary` | `#4F46E5` (Indigo 600) | `#818CF8` (Indigo 400) | Authority hierarchy markers & role badges |
| `colorOnBrandSecondary` | `#FFFFFF` | `#1E1B4B` (Indigo 950) | Text on secondary |
| `colorSecondaryContainer` | `#E0E7FF` (Indigo 100) | `#312E81` (Indigo 900) | Tier chips & level containers |
| `colorOnSecondaryContainer` | `#3730A3` (Indigo 800) | `#C7D2FE` (Indigo 200) | Text on secondary containers |

### B. Surfaces & Backgrounds

| Token Name | Light Mode (HEX) | Dark Mode (HEX) | Purpose |
| :--- | :--- | :--- | :--- |
| `colorBackground` | `#F8FAFC` (Slate 50) | `#0F172A` (Slate 900) | Primary screen canvas |
| `colorSurface` | `#FFFFFF` | `#1E293B` (Slate 800) | Cards, modals, lists, bottom sheets |
| `colorSurfaceElevated` | `#FFFFFF` | `#334155` (Slate 700) | Floating action banners, dropdown menus |
| `colorTextPrimary` | `#0F172A` (Slate 900) | `#F8FAFC` (Slate 50) | High-emphasis body, titles, headings |
| `colorTextMuted` | `#64748B` (Slate 500) | `#94A3B8` (Slate 400) | Timestamps, helper text, secondary info |
| `colorBorder` | `#E2E8F0` (Slate 200) | `#334155` (Slate 700) | Card borders, dividers, text field outlines |
| `colorBorderFocused` | `#0D9488` (Teal 600) | `#14B8A6` (Teal 500) | Active input focus ring |

### C. Complaint Status Indicators (Multi-Token)

| Status Token | Light Mode (HEX) | Dark Mode (HEX) | Description |
| :--- | :--- | :--- | :--- |
| `statusPending` | `#D97706` (Amber 600) | `#FBBF24` (Amber 400) | Submitted, pending intake |
| `statusUnderReview` | `#2563EB` (Blue 600) | `#60A5FA` (Blue 400) | Picked up by authority |
| `statusInProgress` | `#0284C7` (Sky 600) | `#38BDF8` (Sky 400) | Active investigation/remedy |
| `statusEscalated` | `#EA580C` (Orange 600) | `#FB923C` (Orange 400) | Breached tier SLA, forwarded up |
| `statusSlaBreached` | `#DC2626` (Red 600) | `#F87171` (Red 400) | Overdue, requires immediate review |
| `statusCutoffPaused` | `#7C3AED` (Purple 600) | `#C084FC` (Purple 400) | Frozen at 20-day campus cutoff |
| `statusResolved` | `#059669` (Emerald 600) | `#34D399` (Emerald 400) | Closed with resolution memo |
| `statusRejected` | `#64748B` (Slate 500) | `#94A3B8` (Slate 400) | Rejected with official remark |

### D. Data Visualization Chart Palette (`fl_chart`)
* **Series 1 (Academic):** `#0D9488` (Teal)
* **Series 2 (Hostel):** `#4F46E5` (Indigo)
* **Series 3 (Infrastructure):** `#EA580C` (Orange)
* **Series 4 (Finance):** `#059669` (Emerald)
* **Series 5 (IT):** `#0284C7` (Sky)

---

## 2. Typography Hierarchy (Plus Jakarta Sans / Inter)

| Scale Token | Size (sp) | Weight | Line Height (sp) | Intended Use |
| :--- | :--- | :--- | :--- | :--- |
| `typeDisplayLarge` | 28 | Bold (700) | 34 | Top dashboard metric cards |
| `typeHeadlineMedium`| 22 | SemiBold (600) | 28 | Screen titles, page headers |
| `typeTitleLarge` | 18 | SemiBold (600) | 24 | Card headers, modal titles |
| `typeTitleMedium` | 16 | Medium (500) | 22 | Form section headers |
| `typeBodyLarge` | 15 | Regular (400) | 22 | Main complaint descriptions |
| `typeBodyMedium` | 14 | Regular (400) | 20 | Timeline remarks, authority notes |
| `typeLabelMedium` | 12 | Medium (500) | 16 | Status badges, category chips |
| `typeCaption` | 11 | Regular (400) | 14 | Metadata timestamps, file size info |

---

## 3. Spacing Grid & Elevation

* **8pt Spatial Grid:**
  * `space4` (4dp), `space8` (8dp), `space12` (12dp), `space16` (16dp), `space24` (24dp), `space32` (32dp), `space48` (48dp).
* **Corner Radii:**
  * Small: `8dp` (Text fields, buttons, category chips)
  * Medium: `12dp` (Cards, bottom sheets)
  * Large: `16dp` (Dialogs, hero banners)
  * Pill: `999dp` (Status badges)
* **Touch Targets (Android Accessibility Rule):**
  * Every clickable item has a minimum touch target of **`48dp × 48dp`** to prevent tap errors.
* **Elevation & Depth:**
  * Clean, modern flat depth with a `1dp` border (`colorBorder`) on standard cards.
  * Modals and floating action elements use `elevation: 6dp` with soft ambient drop-shadow.

---

## 4. Component Inventory & Standards

### A. Buttons (`PrimaryButton`, `SecondaryButton`, `DangerButton`)
* Height: `48dp` minimum.
* Visual states: Idle, Focused, Pressed, Loading (contained centered spinner), Disabled (40% opacity).

### B. Form Inputs (`AppTextField`, `RestrictedDatePicker`)
* Inputs enforce `8dp` corner radius, distinct floating label, helper text, and clear error text on validation failure.
* `RestrictedDatePicker`: Specifically locks calendar navigation so only dates in `[Today - 7 days, Today]` can be chosen.

### C. Grievance Status Badges (`GrievanceStatusBadge`)
* Pill badge with `icon + text` using the multi-token status colors. Includes the distinctive Purple badge for `20-Day Cutoff Paused`.

### D. Timeline Stepper (`GrievanceTimelineView`)
* Vertical connected nodes illustrating the chronological journey from intake, authority reviews, escalations, to resolution.

---

## 5. Explicit View State Handling

Every screen that fetches, submits, or displays asynchronous data must implement the 5 standard view states:

1. **Loading State:**
   * Uses layout-matched shimmer skeletons (`StateLoadingShimmer`) rather than full-screen blocking spinners.
2. **Empty State:**
   * Displays an explanatory SVG illustration, clear message, and an immediate primary CTA (`StateEmptyView`).
3. **Error State:**
   * Inline alert banner with user-friendly error message and dedicated `Retry` button (`StateErrorView`).
4. **Success State:**
   * Visual checkmark + confirmation bottom sheet + unique grievance tracking ID copy button.
5. **Disabled State:**
   * Muted contrast and disabled interaction on buttons until all form validations pass.

---

## 6. Accessibility & Contrast Verification (WCAG 2.2 AA)

* **Contrast Ratios:**
  * All primary body and header typography achieves at least **4.5:1** contrast against surface backgrounds.
  * Large titles and status indicator badges achieve at least **3.0:1** contrast.
* **Screen Reader Semantics:**
  * All custom interactive elements are wrapped in Flutter `Semantics` widgets with descriptive labels for Android TalkBack.
