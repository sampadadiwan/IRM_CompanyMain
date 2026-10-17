import { Colors, type Palette } from '@/constants/theme';

/**
 * The app's one palette (graphite + mint, see constants/theme.ts). It deliberately does not follow
 * the phone's light / dark setting — the product owner chose one designed look (2026-10-13).
 */
export function useTheme(): Palette {
  return Colors.app;
}
