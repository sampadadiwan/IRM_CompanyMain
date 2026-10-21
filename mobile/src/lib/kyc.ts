import type { Kyc } from '@/api/types';

/** A KYC's status as the LP reads it, from the website's submission_status (verified wins) */
export function kycStatus(kyc: Pick<Kyc, 'submission_status' | 'verified'>): string {
  if (kyc.verified) return 'Verified';
  return ({
    not_sent: 'Not sent', link_sent: 'To complete', draft_saved: 'Draft', completed: 'Submitted', verified: 'Verified',
  } as Record<string, string>)[kyc.submission_status] ?? kyc.submission_status;
}

/** Still the investor's turn: the form is open on the website */
export function kycToComplete(kyc: Pick<Kyc, 'submission_status' | 'verified'>): boolean {
  return !kyc.verified && ['link_sent', 'draft_saved'].includes(kyc.submission_status);
}
