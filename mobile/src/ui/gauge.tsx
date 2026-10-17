import { StyleSheet, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Stop } from 'react-native-svg';

import { useTheme } from '@/hooks/use-theme';
import { AppText } from '@/ui/primitives';

/**
 * The reference's dial, in CapHive orange: a 270° arc of fine dots that brighten from peach to
 * orange up to `value` percent, a thin inner ring with a white knob marking the same point, and a
 * big light-weight figure in the middle. Sits straight on the screen background, no card.
 */
export function Gauge({ value, figure, caption, size = 288, minLabel = '0', maxLabel = '100' }:
  { value: number; figure: string; caption: string; size?: number; minLabel?: string; maxLabel?: string }) {
  const theme = useTheme();
  const pct = Math.max(0, Math.min(100, value));
  const dots = 54;
  const c = size / 2;
  const outer = c - 12;
  const ring = outer - 34;
  const start = 135; // degrees: bottom-left, sweeping clockwise to bottom-right
  const sweep = 270;
  const lit = Math.round((pct / 100) * (dots - 1));
  const at = (deg: number, r: number) => {
    const a = (deg * Math.PI) / 180;
    return { x: c + r * Math.cos(a), y: c + r * Math.sin(a) };
  };
  const knob = at(start + (sweep * pct) / 100, ring);

  return (
    <View style={{ width: size, height: size, alignSelf: 'center' }} accessibilityRole="progressbar"
      accessibilityLabel={`${caption}: ${figure}`} accessibilityValue={{ min: 0, max: 100, now: Math.round(pct) }}>
      <Svg width={size} height={size}>
        <Defs>
          <LinearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor="#FFFFFF" stopOpacity="0.22" />
            <Stop offset="1" stopColor="#FFFFFF" stopOpacity="0.04" />
          </LinearGradient>
        </Defs>
        {Array.from({ length: dots }).map((_, i) => {
          const p = at(start + (sweep * i) / (dots - 1), outer);
          if (i > lit) return <Circle key={i} cx={p.x} cy={p.y} r={2.2} fill={theme.track} opacity={0.55} />;
          // Lit dots fade in along the arc and turn from peach to full orange near the value
          const t = lit === 0 ? 1 : i / lit;
          const color = t > 0.82 ? theme.accent : theme.highlight;
          return <Circle key={i} cx={p.x} cy={p.y} r={2.4 + t * 1.6} fill={color} opacity={0.35 + t * 0.65} />;
        })}
        <Circle cx={c} cy={c} r={ring} stroke="url(#ring)" strokeWidth={1.5} fill="transparent" />
        <Circle cx={knob.x} cy={knob.y} r={7} fill={theme.inverse} />
        <Circle cx={knob.x} cy={knob.y} r={2.5} fill={theme.accent} />
      </Svg>
      <View style={[StyleSheet.absoluteFill, styles.middle]}>
        <AppText variant="hero">{figure}</AppText>
        <AppText color="textSecondary">{caption}</AppText>
      </View>
      <AppText variant="caption" color="textSecondary" style={[styles.edge, { left: size * 0.17 }]}>{minLabel}</AppText>
      <AppText variant="caption" color="textSecondary" style={[styles.edge, { right: size * 0.15 }]}>{maxLabel}</AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  middle: { alignItems: 'center', justifyContent: 'center' },
  edge: { position: 'absolute', bottom: 34 },
});
