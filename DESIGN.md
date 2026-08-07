# Pusaka Design System

Single source of truth for styling across all three Flutter apps (Customer, QR,
Staff — `--dart-define=APP_MODE=customer|qr|staff`). Derived visually from the
"Pusaka — Modern Indonesian Heritage" screen set (home, product detail, menu,
basket, checkout, receipt, reservation, bookings, order tracking, login,
chatbot widget, order history).

> **Status note:** hex values below are estimated by eye from screenshots, not
> pulled from a source file (Figma/Stitch export wasn't available — the Stitch
> MCP server is currently broken server-side). Treat them as "close enough to
> build with"; nudge them against the real design file if pixel-perfect match
> matters later.
>
> **This does not match the current codebase yet.** [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart)
> today defines a navy/pink palette (`AppColors.primary = #1A1A2E`,
> `AppColors.accent = #E94560`) built for the staff/KDS app. This document
> describes the *target* Pusaka system seen in the customer-facing screens —
> adopting it means reworking `app_theme.dart`, not just adding to it. Do that
> as a deliberate follow-up task, not silently.

---

## 1. Color Tokens

| Token | Hex (approx) | Usage |
|---|---|---|
| `background` | `#FAF6ED` | App background, page canvas (warm cream, consistent across every screen) |
| `surface` | `#FDFBF5` | Cards, input fields, panels sitting on `background` |
| `surfaceMuted` | `#F1EDE2` | Subtle fill for secondary panels (e.g. checkout "Service Type" box) |
| `footerBackground` | `#E2DED4` | Footer band (slightly darker than background) |
| `border` | `#E4DFD2` | Card borders, dividers, input underlines |
| `primary` (gold/mustard) | `#C08A17` | Logo wordmark, primary CTAs ("Explore Menu", "Sign In", "Confirm Reservation", "Track Order"), status dots, chatbot header |
| `accent` (terracotta/rust) | `#A6491F` | Secondary CTAs with more urgency ("Add to Cart", "ADD TO CART", "Place Order", "Back to Home") |
| `textPrimary` | `#221F1B` | Headings, body copy, prices |
| `textSecondary` | `#6E6A63` | Descriptions, meta text, placeholder-adjacent labels |
| `textHint` | `#9C9690` | Placeholder text in inputs |
| `statusConfirmed` | `#C08A17` (= primary) | "Confirmed" / "Open" dots |
| `statusWaitlist` | `#D97706` | "Waitlist" badge |
| `statusCompleted` | `#9C9690` | "Completed" badge (muted) |
| `statusClosed` | `#E8A0A0` | "Closed" indicator dot |
| `badgeDark` (accent navy) | `#22284A` | "DISH OF THE MONTH" ribbon badge — one-off contrast accent, not reused elsewhere |
| `iconAccentBlue` | `#4C5FD5` | Small inline accents (spice-level icon) — sparse use |

Notes:
- There is no "error red" distinct from `accent` in these screens — checkout/
  destructive actions ("Remove") use plain text, not a red token. Introduce a
  proper error color when validation states are designed; don't reuse `accent`
  for errors since it's also the primary secondary-CTA color.
- Dark mode is not represented in any of the reference screens — all 12 are
  light. Don't assume a dark variant exists; design one separately if needed.

---

## 2. Typography

Two distinct type families are visible:

1. **Display / heading font** — a rounded, bold geometric sans (soft
   terminals on "a", "u", "s"). Visually close to **Baloo 2** or **Fredoka**
   (bold weights). Used for: logo wordmark, hero titles ("Pusaka", "Your
   Basket", "Reserve a Table", "My Bookings", "Order History", "Order #8492",
   "Terima Kasih").
2. **Body / UI font** — a clean, neutral grotesque sans, similar weight/metrics
   to **Inter** or **Work Sans** (the codebase's current `Poppins` is a
   reasonable stand-in but reads slightly more geometric/rounded than what's
   shown — verify against the actual export if exact match matters). Used for
   nav, body copy, buttons, form fields, prices.
3. One accent detail: the order confirmation code ("`#PSK-8924`") is set in an
   **italic serif** (e.g. Playfair Display Italic), a one-off ceremonial touch
   for receipt/confirmation moments — not a general-purpose token.

### Type scale (approx, base 16px)

| Style | Size | Weight | Font | Example |
|---|---|---|---|---|
| `display` | 40–48px | Bold (700) | Display/rounded | "Pusaka" hero, "Your Basket" |
| `h1` | 32–36px | Bold (700) | Display/rounded | "Reserve a Table", "My Bookings" |
| `h2` | 24–28px | Bold (700) | Display/rounded | "Rendang Daging Sapi", "Our Locations" |
| `h3` | 18–20px | Semibold (600) | Body | Card titles ("Ubud", "Nasi Campur Bali") |
| `body` | 15–16px | Regular (400) | Body | Descriptions, cart items |
| `bodyEmphasis` | 15–16px | Semibold (600) | Body | Prices, item names in lists |
| `label` | 11–12px | Semibold (600), uppercase, tracked | Body | "SPICE LEVEL", "ADD-ONS", "STATUS", "ORDER SUMMARY" |
| `caption` | 12–13px | Regular (400) | Body | Meta text ("1.2 km away", timestamps) |
| `confirmationCode` | 22–24px | Italic | Serif accent | "`#PSK-8924`" only |

---

## 3. Spacing & Radius

| Token | Value | Usage |
|---|---|---|
| `radiusSm` | 8px | Inputs, small buttons, checkboxes |
| `radiusMd` | 12px | Cards, product images |
| `radiusLg` | 16px | Large panels (checkout summary, reservation form) |
| `radiusPill` | 24px+ / full | Chatbot FAB, some tags |
| `spaceXs` | 8px | Tight internal gaps (icon-to-label) |
| `spaceSm` | 16px | Internal card padding, form field gaps |
| `spaceMd` | 24px | Grid gutters (menu cards, location cards), section-internal spacing |
| `spaceLg` | 32px | Between sub-sections |
| `spaceXl` | 48px+ | Page margins, hero section spacing |

Buttons: solid fill, no border, `radiusSm`–`radiusMd` corners, generous
horizontal padding (~24px). Primary (gold) and secondary (terracotta) both
appear as solid-fill — outline style is reserved for tertiary actions ("View
Details", "Manage", "REMOVE").

Cards: 1px `border` stroke + `radiusMd`, no drop shadow visible in any
screen — flat design throughout.

---

## 4. Component Notes

- **Status badges** (bookings, order tracking): small dot + uppercase label,
  no filled pill background — color carried entirely by the dot + text color.
- **Stepper** (order tracking "Received → Preparing → Ready → Served"):
  filled dot = current/past step in `primary`, hollow/pale dot = future step.
- **Radio/checkbox groups** (spice level, add-ons, payment method): full-row
  tap targets with a divider between rows, not boxed individual cards.
- **Chatbot widget**: floating pill FAB (`accent`/`primary` gold), expands to
  a panel with gold header bar, rounded quick-reply chips.

---

## 5. Open Questions / TODO

- [ ] Confirm exact font names (display font looks like Baloo 2/Fredoka; get
      the real family + weights used).
- [ ] Confirm exact hex values against the actual Stitch/Figma source once the
      Stitch MCP server's schema bug is fixed (currently returns
      `can't resolve reference #/$defs/ScreenInstance` on tool list).
- [ ] Decide whether `app_theme.dart`'s navy/pink `AppColors` (staff/KDS app)
      stays as-is or gets folded into this system — the two are currently
      unrelated palettes serving different app modes.
- [ ] No dark-mode reference exists yet for the Pusaka palette.
