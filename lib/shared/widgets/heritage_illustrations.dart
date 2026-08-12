// Hand-authored flat-vector illustrations for the customer app, drawn to
// match the warm gold/terracotta "Cita Rasa" palette (AppColors.primary
// #C08A17, AppColors.accent #A6491F) instead of relying on a stock photo or
// a single centered Material icon. Kept as inline SVG (SvgPicture.string)
// rather than asset files so there's nothing to register in pubspec.yaml.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Landing-page hero art: a plated satay-and-rice scene, used in place of
/// the previous plain gradient box + restaurant icon.
class HeroPlatterIllustration extends StatelessWidget {
  const HeroPlatterIllustration({super.key});

  static const _svg = '''
<svg viewBox="0 0 400 400" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="200" cy="332" rx="148" ry="16" fill="#000000" opacity="0.10"/>
  <ellipse cx="200" cy="230" rx="150" ry="108" fill="#FDFBF5"/>
  <ellipse cx="200" cy="230" rx="150" ry="108" fill="none" stroke="#F1EDE2" stroke-width="3"/>
  <ellipse cx="200" cy="222" rx="118" ry="84" fill="none" stroke="#EADFC4" stroke-width="2"/>
  <ellipse cx="150" cy="200" rx="62" ry="46" fill="#FBF3DD"/>
  <ellipse cx="150" cy="200" rx="62" ry="46" fill="none" stroke="#EAD9AE" stroke-width="1.5"/>
  <circle cx="128" cy="188" r="2.4" fill="#EAD9AE"/>
  <circle cx="145" cy="178" r="2.4" fill="#EAD9AE"/>
  <circle cx="168" cy="190" r="2.4" fill="#EAD9AE"/>
  <circle cx="155" cy="210" r="2.4" fill="#EAD9AE"/>
  <circle cx="132" cy="212" r="2.4" fill="#EAD9AE"/>
  <circle cx="178" cy="205" r="2.4" fill="#EAD9AE"/>
  <g transform="rotate(-18 260 210)">
    <rect x="228" y="207" width="112" height="6" rx="3" fill="#C9A257"/>
    <rect x="238" y="197" width="20" height="24" rx="6" fill="#A6491F"/>
    <rect x="262" y="197" width="20" height="24" rx="6" fill="#8A3A18"/>
    <rect x="286" y="197" width="20" height="24" rx="6" fill="#A6491F"/>
    <rect x="310" y="197" width="20" height="24" rx="6" fill="#8A3A18"/>
  </g>
  <g transform="rotate(-6 260 250)">
    <rect x="228" y="247" width="112" height="6" rx="3" fill="#C9A257"/>
    <rect x="238" y="237" width="20" height="24" rx="6" fill="#8A3A18"/>
    <rect x="262" y="237" width="20" height="24" rx="6" fill="#A6491F"/>
    <rect x="286" y="237" width="20" height="24" rx="6" fill="#8A3A18"/>
    <rect x="310" y="237" width="20" height="24" rx="6" fill="#A6491F"/>
  </g>
  <circle cx="118" cy="268" r="26" fill="#B4501F"/>
  <circle cx="118" cy="268" r="20" fill="#D9601F"/>
  <circle cx="118" cy="268" r="20" fill="none" stroke="#A6491F" stroke-width="2"/>
  <path d="M186 158 C182 140 194 128 210 126 C202 140 200 152 196 162 Z" fill="#7C9A5C"/>
  <path d="M198 160 C196 146 206 136 218 134 C212 146 210 154 208 164 Z" fill="#8FAE6C"/>
  <path d="M150 130 C142 118 156 112 150 98" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" fill="none" opacity="0.75"/>
  <path d="M172 126 C164 114 178 108 172 94" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" fill="none" opacity="0.6"/>
  <circle cx="330" cy="90" r="34" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-dasharray="4 6" opacity="0.5"/>
</svg>
''';

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_svg, fit: BoxFit.contain);
}

/// Booking-screen side art: a top-down reserved-table scene, used in place
/// of the previous empty surface box with a bare restaurant icon.
class TableReservationIllustration extends StatelessWidget {
  const TableReservationIllustration({super.key});

  static const _svg = '''
<svg viewBox="0 0 380 380" xmlns="http://www.w3.org/2000/svg">
  <circle cx="190" cy="200" r="170" fill="#EADFC4"/>
  <circle cx="190" cy="200" r="170" fill="none" stroke="#DDCBA0" stroke-width="2"/>
  <circle cx="190" cy="200" r="150" fill="none" stroke="#E3D3AC" stroke-width="1" stroke-dasharray="2 10" opacity="0.6"/>
  <circle cx="190" cy="205" r="72" fill="#FDFBF5"/>
  <circle cx="190" cy="205" r="72" fill="none" stroke="#F1EDE2" stroke-width="3"/>
  <circle cx="190" cy="205" r="52" fill="none" stroke="#EADFC4" stroke-width="1.5"/>
  <g fill="#C08A17">
    <rect x="84" y="150" width="8" height="110" rx="4"/>
    <rect x="74" y="140" width="6" height="30" rx="3"/>
    <rect x="84" y="140" width="6" height="30" rx="3"/>
    <rect x="94" y="140" width="6" height="30" rx="3"/>
  </g>
  <g fill="#C08A17">
    <rect x="288" y="150" width="8" height="110" rx="4"/>
    <path d="M282 140 h20 c4 10 -2 22 -10 22 c-8 0 -14 -12 -10 -22 Z"/>
  </g>
  <g transform="translate(190 118)">
    <path d="M-34 0 L0 -26 L34 0 Z" fill="#FDFBF5" stroke="#EADFC4" stroke-width="1.5"/>
    <text x="0" y="-4" text-anchor="middle" font-family="sans-serif" font-size="10" font-weight="700" fill="#A6491F" letter-spacing="1">RESERVED</text>
  </g>
  <g transform="translate(190 330)">
    <rect x="-9" y="-4" width="18" height="34" rx="4" fill="#FDFBF5" stroke="#EADFC4" stroke-width="1.5"/>
    <path d="M0 -6 C-6 -14 6 -20 0 -30 C6 -22 8 -12 0 -6 Z" fill="#C08A17"/>
  </g>
  <g transform="translate(96 300)" stroke="#7C9A5C" stroke-width="2.5" stroke-linecap="round" fill="none">
    <path d="M0 20 C-4 4 4 -8 0 -20"/>
    <path d="M0 4 C-8 0 -12 -8 -10 -14"/>
    <path d="M0 -6 C8 -10 10 -18 8 -22"/>
  </g>
</svg>
''';

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_svg, fit: BoxFit.contain);
}
