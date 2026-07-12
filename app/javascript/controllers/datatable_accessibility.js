// Shared accessibility helper for jQuery DataTables instances.
// Adds an ARIA navigation label to the pagination controls and per-button
// labels (First/Previous/Next/Last/Page N) so screen readers announce
// something more useful than the raw glyphs («, ‹, ›, », digits).

export function setupAccessibleSorting(table) {
  const header = $(table.table().header());
  const allHeaders = header.find('th');
  const order = table.order();

  if (!allHeaders.length) return;

  allHeaders.attr('aria-sort', 'none');

  if (!Array.isArray(order) || !order.length) return;

  // DataTables reports sorting by visible column index.
  const [sortedColumnIndex, direction] = order[0];
  const sortedHeader = allHeaders.eq(sortedColumnIndex);
  if (!sortedHeader.length) return;

  const ariaValue = direction === 'desc' ? 'descending' : 'ascending';
  sortedHeader.attr('aria-sort', ariaValue);
}

export function setupAccessiblePagination(table) {
  const wrapper = $(table.table().container());
  const paginate = wrapper.find('.dt-paging, .dataTables_paginate');

  setupAccessibleSorting(table);

  if (!paginate.length) return;

  paginate.attr('role', 'navigation');
  paginate.attr('aria-label', 'Pagination');

  paginate.find('a, button').each(function() {
    const el = $(this);
    const rawText = (el.text() || '').trim();
    let label = rawText;

    if (rawText === '«' || rawText === '<<') label = 'First page';
    else if (rawText === '‹' || rawText === '<') label = 'Previous page';
    else if (rawText === '›' || rawText === '>') label = 'Next page';
    else if (rawText === '»' || rawText === '>>') label = 'Last page';
    else if (/^\d+$/.test(rawText)) label = `Page ${rawText}`;

    if (label.length > 0) {
      el.attr('aria-label', label);
    }
  });
}
