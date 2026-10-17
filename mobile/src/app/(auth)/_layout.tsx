import { Stack } from 'expo-router';

import { useAuth } from '@/auth/session';

/** Region → Sign in → Code (proposal Workflow Journey A1–A4) */
export default function AuthLayout() {
  const { status } = useAuth();
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={status === 'needsRegion'}>
        <Stack.Screen name="region" />
      </Stack.Protected>
      <Stack.Protected guard={status === 'signedOut'}>
        <Stack.Screen name="sign-in" />
      </Stack.Protected>
      <Stack.Protected guard={status === 'code'}>
        <Stack.Screen name="code" />
      </Stack.Protected>
    </Stack>
  );
}
