import { Manrope_300Light, Manrope_400Regular, Manrope_500Medium, Manrope_600SemiBold, useFonts } from '@expo-google-fonts/manrope';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect, useState } from 'react';
import { AppState, StyleSheet, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { AuthProvider, useAuth } from '@/auth/session';
import { useTheme } from '@/hooks/use-theme';

SplashScreen.preventAutoHideAsync();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Show cached data first, then refresh (proposal principle 7); keep it for the offline bar
      staleTime: 30_000,
      gcTime: 24 * 60 * 60 * 1000,
      retry: (count, error) => count < 2 && !(error instanceof Error && 'status' in error && [401, 403, 404, 426].includes(Number((error as { status: number }).status))),
    },
  },
});

/** Screens refresh when the app comes back to the foreground (proposal "UI Behavior") */
function useRefetchOnForeground() {
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active') queryClient.invalidateQueries();
    });
    return () => sub.remove();
  }, []);
}

function Navigator() {
  const { status } = useAuth();
  // The app's typeface; the splash stays up until it is ready so text never jumps
  const [fontsLoaded] = useFonts({ Manrope_300Light, Manrope_400Regular, Manrope_500Medium, Manrope_600SemiBold });
  const theme = useTheme();
  useRefetchOnForeground();

  useEffect(() => {
    if (status !== 'loading' && fontsLoaded) SplashScreen.hideAsync();
    // Signing out (or being signed out) drops everything cached for the previous session
    if (status === 'signedOut' || status === 'needsRegion') queryClient.clear();
  }, [status, fontsLoaded]);

  if (status === 'loading' || !fontsLoaded) return null;

  const navTheme = DefaultTheme;
  return (
    <ThemeProvider value={{ ...navTheme, colors: { ...navTheme.colors, background: theme.background, card: theme.surface, primary: theme.accent, text: theme.text, border: theme.border } }}>
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: theme.background } }}>
        <Stack.Protected guard={status === 'needsRegion' || status === 'signedOut' || status === 'code'}>
          <Stack.Screen name="(auth)" options={{ headerShown: false }} />
        </Stack.Protected>
        <Stack.Protected guard={status === 'signedIn'}>
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="funds/[id]" />
          <Stack.Screen name="capital-calls/[id]" />
          <Stack.Screen name="distributions/[id]" />
          <Stack.Screen name="documents/[id]" />
          <Stack.Screen name="profile/notifications" />
        </Stack.Protected>
        <Stack.Protected guard={status === 'locked'}>
          <Stack.Screen name="locked" options={{ headerShown: false }} />
        </Stack.Protected>
        <Stack.Protected guard={status === 'updateRequired'}>
          <Stack.Screen name="update" options={{ headerShown: false }} />
        </Stack.Protected>
      </Stack>
    </ThemeProvider>
  );
}

/** Covers the app in the system app switcher (proposal principle 10) */
function PrivacyCover() {
  const theme = useTheme();
  const [inactive, setInactive] = useState(false);
  useEffect(() => {
    const sub = AppState.addEventListener('change', (s) => setInactive(s !== 'active'));
    return () => sub.remove();
  }, []);
  if (!inactive) return null;
  return <View style={[StyleSheet.absoluteFill, { backgroundColor: theme.background }]} />;
}

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <Navigator />
          <PrivacyCover />
        </AuthProvider>
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}
