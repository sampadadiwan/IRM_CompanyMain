import { router, type Href } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { Alert, Platform } from 'react-native';

import { webHandoffUrl } from '@/api/queries';

/**
 * Where a tap goes (design card ① flowchart): a notification's or To do item's link is either an
 * app route ("/capital-calls/9031") or "web:<path>" for something the app has no screen for
 * (approvals, KYC, evergreen subscribe…). Web links open the website page in the in-app browser,
 * already signed in through a one-time hand-off link — so the app is never a dead end.
 */
export async function openLink(link: string) {
  if (link.startsWith('web:')) return openWebsitePage(link.slice(4));
  router.push(link as Href);
}

export async function openWebsitePage(path: string) {
  try {
    const url = await webHandoffUrl(path);
    if (Platform.OS === 'web') {
      globalThis.open?.(url, '_blank');
      return;
    }
    await WebBrowser.openBrowserAsync(url, { presentationStyle: WebBrowser.WebBrowserPresentationStyle.PAGE_SHEET });
  } catch (error) {
    Alert.alert('This page can\'t be opened', error instanceof Error ? error.message : 'Please try again.');
  }
}

/** Documents: iOS shows PDFs in the in-app browser; Android hands them to the PDF viewer */
export async function openDocumentFile(url: string) {
  if (Platform.OS === 'web') {
    globalThis.open?.(url, '_blank');
    return;
  }
  await WebBrowser.openBrowserAsync(url, { presentationStyle: WebBrowser.WebBrowserPresentationStyle.PAGE_SHEET });
}

/** Digio's signing page in an auth session; the screen refetches the status when it closes (H18) */
export async function openSigning(url: string) {
  if (Platform.OS === 'web') {
    globalThis.open?.(url, '_blank');
    return;
  }
  await WebBrowser.openAuthSessionAsync(url);
}
