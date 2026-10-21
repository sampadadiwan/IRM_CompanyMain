import { Fragment, type ReactNode } from 'react';

import { Card, Divider, EmptyState, ErrorState, SkeletonCard } from '@/ui/primitives';

type ListQuery<T> = { data?: T[]; isPending: boolean; isError: boolean; error: Error | null; refetch: () => unknown };

/** One query's rows in a card: skeleton while loading, retry on error, an empty state, else the rows */
export function ListCard<T extends { id: number }>({ query, render, empty }: { query: ListQuery<T>; render: (row: T) => ReactNode; empty: string }) {
  if (query.isPending) return <SkeletonCard lines={3} />;
  if (query.isError) return <ErrorState message={query.error?.message ?? 'Something went wrong.'} onRetry={() => query.refetch()} />;
  if (!query.data?.length) return <EmptyState icon="doc.text" title={empty} />;
  return (
    <Card>
      {query.data.map((row, i) => (
        <Fragment key={row.id}>
          {i > 0 ? <Divider /> : null}
          {render(row)}
        </Fragment>
      ))}
    </Card>
  );
}
