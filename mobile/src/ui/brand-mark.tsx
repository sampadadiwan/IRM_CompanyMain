import Svg, { Path } from 'react-native-svg';

import { useTheme } from '@/hooks/use-theme';

/** The CapHive hexagon mark — the same geometry as public/icon.svg and the website favicon */
export function BrandMark({ size = 26 }: { size?: number }) {
  const theme = useTheme();
  return (
    <Svg width={size} height={size} viewBox="0 0 34 34" accessibilityLabel="CapHive">
      <Path d="M17 1L31 9v16L17 33 3 25V9L17 1z" fill="none" stroke={theme.accent} strokeWidth={3} />
      <Path d="M17 9l7 4v8l-7 4-7-4v-8l7-4z" fill={theme.accent} />
    </Svg>
  );
}
