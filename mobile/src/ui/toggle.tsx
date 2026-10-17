import { Platform, Switch, type SwitchProps } from 'react-native';

import { useTheme } from '@/hooks/use-theme';

/** The app's switch: CapHive orange when on, a white thumb on every platform (web needs activeThumbColor) */
export function Toggle(props: SwitchProps) {
  const theme = useTheme();
  const web = Platform.OS === 'web' ? ({ activeThumbColor: '#FFFFFF', activeTrackColor: theme.accent } as object) : {};
  return <Switch trackColor={{ true: theme.accent, false: theme.track }} thumbColor="#FFFFFF" {...web} {...props} />;
}
