/**
 * One visual system for the whole app, after the MYGRID concept the product owner chose
 * (dribbble.com/shots/24230360, 2026-10-13) with a CapHive orange accent: soft graphite surfaces —
 * never flat black — large light-weight numerals, pill controls, round icon buttons and a floating
 * tab bar. CapHive orange (#FF4D00, the brand mark in public/icon.svg) is the one accent; green,
 * amber and red are only for status and always come with an icon or label (proposal principle 5).
 * One fixed palette: the app does not switch with the phone's dark mode.
 */
import { Platform } from 'react-native';

export const Colors = {
  app: {
    text: '#F4F3F1',
    textSecondary: '#9C9FA5',
    background: '#1F2023',
    backgroundTop: '#2A2B2F',
    surface: '#2C2E32',
    surfaceAlt: '#383A3F',
    border: '#3A3D42',
    // CapHive orange
    accent: '#FF4D00',
    accentSoft: '#3A2A22',
    onAccent: '#FFFFFF',
    // Peach from the CapHive mark, for secondary marks (gauge tail, chart highlights)
    highlight: '#FDA57D',
    inverse: '#F4F3F1',
    onInverse: '#1C1D20',
    success: '#7FD6A0',
    successSoft: '#26352C',
    warning: '#F2C46B',
    warningSoft: '#3A3324',
    danger: '#F2907A',
    dangerSoft: '#3D2A26',
    skeleton: '#36383D',
    track: '#45484E',
    // Depth: a lighter graphite at the top of the screen and of each card, and a faint light edge
    screenTop: '#2E3034',
    screenBottom: '#18191B',
    cardTop: '#33353A',
    cardBottom: '#26282C',
    hairline: 'rgba(255,255,255,0.07)',
  },
} as const;

export type ThemeColor = keyof typeof Colors.app;
export type Palette = { [K in ThemeColor]: string };

/**
 * Manrope — a light, geometric face like the reference's. Big figures use the Light cut (the
 * number is the hero); labels use Regular/Medium; nothing heavier than SemiBold.
 */
export const Family = {
  light: 'Manrope_300Light',
  regular: 'Manrope_400Regular',
  medium: 'Manrope_500Medium',
  semibold: 'Manrope_600SemiBold',
} as const;

/** One type scale. Weight comes from the font family (custom fonts ignore fontWeight on Android). */
export const Type = {
  hero: { fontFamily: Family.light, fontSize: 52, lineHeight: 58, letterSpacing: -1.5, fontVariant: ['tabular-nums'] as const },
  title: { fontFamily: Family.regular, fontSize: 32, lineHeight: 38, letterSpacing: -0.8 },
  heading: { fontFamily: Family.medium, fontSize: 17, lineHeight: 23, letterSpacing: -0.2 },
  body: { fontFamily: Family.regular, fontSize: 15, lineHeight: 21 },
  bodyStrong: { fontFamily: Family.semibold, fontSize: 15, lineHeight: 21 },
  caption: { fontFamily: Family.regular, fontSize: 12.5, lineHeight: 17, letterSpacing: 0.1 },
  figure: { fontFamily: Family.light, fontSize: 30, lineHeight: 36, letterSpacing: -0.8, fontVariant: ['tabular-nums'] as const },
};

export const Fonts = Platform.select({
  ios: { sans: 'system-ui', serif: 'ui-serif', rounded: 'ui-rounded', mono: 'ui-monospace' },
  default: { sans: 'normal', serif: 'serif', rounded: 'normal', mono: 'monospace' },
  web: { sans: 'Inter, system-ui, sans-serif', serif: 'Georgia, serif', rounded: 'system-ui', mono: 'ui-monospace, monospace' },
});

export const Spacing = { half: 2, one: 4, two: 8, three: 16, four: 24, five: 32, six: 64 } as const;
export const Radius = { card: 28, tile: 24, control: 999, pill: 999 } as const;
/** Minimum touch target (proposal principle 9) */
export const TouchTarget = 44;
/** Room the floating tab bar takes at the bottom of tab screens */
export const BottomTabInset = 96;
export const MaxContentWidth = 560;
