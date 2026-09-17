#!/usr/bin/env node
// Generates caphive.com blog articles from the LinkedIn draft markdown in
// docs/marketing/linkedin_posts/. Nav + footer are lifted verbatim from an
// existing article so the generated pages can never drift from the site chrome.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = '/home/thimmaiah/work/IRM';
const SRC = path.join(ROOT, 'docs/marketing/linkedin_posts');
// public/website is the golden source for caphive.com — edit it directly.
// (lib/tasks/website.rake still calls it a mirror of ../caphive.com; that
// comment is stale. Don't run `rake website:sync` — it would --delete this.)
const OUT = process.env.SITE_OUT || path.join(ROOT, 'public/website');
const TMP = process.env.MMD_CACHE || '/tmp/caphive-blog-mmd';
fs.mkdirSync(TMP, { recursive: true });

// ---------------------------------------------------------------- post table
// One entry per generated page. `tint` picks the hero treatment already in
// caphive.css; `chip` is the category label shown above the headline.
const POSTS = [
  // ---- the four earlier drafts (different marker conventions, see buildBody)
  { md: '01_cash_flow_assistant_agent.md', slug: 'cash-flow-agent', chip: 'Fund finance',
    tint: 'tint-black tint-deep', crumb: 'The cash flow agent', read: '8 min read',
    bodyStart: '\n## Article\n', bodyEnd: '\n## Images to prepare before publishing',
    h1: 'The cash flow agent that <em>refuses to answer.</em>',
    desc: 'Fund runway, capital call sizing across SPVs, and why the most important feature of our cash flow agent is saying “not with this data”.',
    card: 'Fund runway and capital call sizing across SPVs — and why the most important thing this agent does is refuse to answer when the underlying data is stale.' },
  { md: '02_customer_support_agent.md', slug: 'how-do-you-know-when-your-bot-is-wrong', chip: 'AI',
    tint: 'tint-orange tint-deep', crumb: 'Grading the support agent', read: '7 min read',
    bodyStart: '\n## Article\n', bodyEnd: '\n## Paste-ready post text',
    h1: 'How do you know <em>when your bot is wrong?</em>',
    desc: 'We put an AI support agent inside our fund platform. Then we built a second AI whose only job is to grade the first one — every answer, scored out of nine.',
    card: 'Every vendor can show you their agent answering correctly. The harder question is how they find out when it answered badly — and what happens to that answer next.' },
  { md: '03_allocation_engine_fund_formulas.md', slug: 'allocation-engine', chip: 'Fund finance',
    tint: 'tint-white', crumb: 'The allocation engine', read: '9 min read',
    bodyStart: '\n## Article body', bodyEnd: '\n## Feed teaser',
    h1: 'Every generated number should carry <em>its own receipt.</em>',
    desc: 'Allocation runs that generate a hundred thousand numbers in minutes — each one storing the formula and the actual input values that produced it.',
    card: 'When an auditor asks you to walk through a number, the answer should not be a reconstruction. How allocation runs store the formula and the input values behind every entry they create.' },
  { md: '04_kpi_portfolio_monitoring.md', slug: 'portfolio-kpis-at-scale', chip: 'Portfolios',
    tint: 'tint-orange tint-deep', crumb: 'Portfolio KPIs at scale', read: '9 min read',
    bodyStart: '\n## Article body', bodyEnd: '\n## Diagrams',
    h1: 'The portfolio <em>that reports itself.</em>',
    desc: 'KPI collection as a monitored pipeline — self-reporting links, staged approvals, dashboards that update on approval, and the agents that keep every quarter honest.',
    card: 'Thirty companies, thirty templates, three weeks of chasing. What changes when collection becomes a monitored workflow instead of a mailbox — and reminders stop themselves.' },
  // ---- the nine newer drafts
  { md: '05_side_letter_obligations.md', slug: 'side-letter-obligations', chip: 'Investor relations',
    tint: 'tint-orange tint-deep', crumb: 'Side letter obligations', read: '9 min read',
    h1: 'Your side letters are in a folder. Your obligations are <em>on your balance sheet.</em>',
    desc: 'Every side letter you sign creates work that outlives the person who negotiated it. How to turn that from institutional memory into a tracked, owned, auditable list.',
    card: 'Every side letter creates work that outlives the person who negotiated it. Turning that from institutional memory into a tracked, owned list — with a clause citation behind every line.' },
  { md: '06_mcp_ai_client.md', slug: 'fund-data-in-your-ai-client', chip: 'AI',
    tint: 'tint-black tint-deep', crumb: 'Fund data in your AI client', read: '8 min read',
    h1: 'We didn’t add a chatbot. We made <em>the fund callable.</em>',
    desc: 'Twenty-two read-only tools, your own API key, your own model. Why the most useful AI feature we shipped this year has no interface of its own.',
    card: 'Every vendor shipped a chat box. The opposite move — making fund data callable from the AI client your team already uses, read-only, under your keys — is the harder and more useful one.' },
  { md: '07_lp_crm.md', slug: 'lp-relationship-crm', chip: 'Investor relations',
    tint: 'tint-orange tint-deep', crumb: 'The LP CRM', read: '9 min read',
    h1: 'Your CRM ends at “Committed.” That’s exactly <em>where the work starts.</em>',
    desc: 'Most funds run the raise in one system and their investors in another. The handover between them is where relationship history goes to die.',
    card: 'A generic CRM models a deal that closes. A fund needs a record that keeps going for twelve years after it closes — through calls, distributions, an AGM and a re-up.' },
  { md: '08_data_rooms.md', slug: 'data-rooms', chip: 'Fund operations',
    tint: 'tint-white', crumb: 'Data rooms', read: '9 min read',
    h1: 'You’re renting a filing cabinet by the page. It can’t <em>read anything inside it.</em>',
    desc: 'The virtual data room is the last piece of fund infrastructure still priced like it is 2009 — and the only one that goes dark the moment the deal closes.',
    card: 'The VDR is the last piece of fund infrastructure priced by the page, and the only one that goes dark at close. What changes when the documents sit where your agents can read them.' },
  { md: '09_distribution_readiness.md', slug: 'distribution-readiness', chip: 'Fund finance',
    tint: 'tint-black tint-deep', crumb: 'Distribution readiness', read: '7 min read',
    h1: 'Five things that must be true before a distribution <em>leaves the building.</em>',
    desc: 'Nobody wires the wrong amount to the wrong account because they were careless. They do it because the checklist was in someone’s head, and that someone was on leave.',
    card: 'Ask three people on the same team for the release checklist and you get three different lists. What it looks like when the checklist is executable, and why "pending" must never render as "passed".' },
  { md: '10_call_notice.md', slug: 'capital-call-notices', chip: 'Fund finance',
    tint: 'tint-orange tint-deep', crumb: 'Capital call notices', read: '7 min read',
    h1: 'The most expensive email <em>your fund sends.</em>',
    desc: 'A capital call notice is a legal instruction to move money, sent to everyone who trusts you with theirs. It deserves a pre-flight checklist nobody can configure away.',
    card: 'A capital call notice is a legal instruction to move money, sent to everyone who trusts you with theirs. Why its pre-flight checklist has no settings at all.' },
  { md: '11_carry_net_irr.md', slug: 'carry-and-net-irr', chip: 'Fund finance',
    tint: 'tint-white', crumb: 'Carry and Net IRR', read: '8 min read',
    h1: 'The 20% in your LPA <em>doesn’t compute anything.</em>',
    desc: 'The carry percentage recorded against a unit class deducts precisely nothing. That is not an oversight — it is the whole design.',
    card: 'Carry reaches performance through exactly one explicit line item, not through a percentage in a settings screen. Why implicit multipliers make performance numbers undefendable.' },
  { md: '12_tracking_currency.md', slug: 'tracking-currency', chip: 'Fund finance',
    tint: 'tint-black tint-deep', crumb: 'Tracking currency', read: '6 min read',
    h1: 'Converting currency is trivial. Choosing the date <em>is the whole job.</em>',
    desc: 'If your firm runs funds in more than one currency, there is a table somewhere in your process that nobody has written down — and everyone is applying differently.',
    card: 'Eight record types, eight different rate dates. The table that decides whether your consolidated view is consistent — and which almost no multi-currency GP has written down.' },
  { md: '13_kyc_document_first.md', slug: 'document-first-kyc', chip: 'Fund operations',
    tint: 'tint-orange tint-deep', crumb: 'Document-first KYC', read: '8 min read',
    h1: 'Stop asking people to type <em>what’s already on their passport.</em>',
    desc: 'Investor onboarding doesn’t get abandoned because the form is long. It gets abandoned because the form asks for information the investor has already given you.',
    card: 'Onboarding is abandoned because the form asks for what the investor already uploaded. Inverting the order — and the audit that runs before anyone relies on the record.' },
];

const DATE = '2026-08-09';
const DATE_LABEL = 'Aug 9, 2026';

// ------------------------------------------------------------------ chrome
// Pull the nav + footer straight out of a hand-authored page so generated
// articles inherit any future edits to the site chrome by regenerating.
const REF = fs.readFileSync(path.join(OUT, 'ai-agent-infrastructure.html'), 'utf8');
const NAV = REF.slice(REF.indexOf('<!-- ================= NAV ================= -->'),
                      REF.indexOf('<article>'));
const FOOT = REF.slice(REF.indexOf('<!-- ================= CTA ================= -->'),
                       REF.indexOf('<script type="application/ld+json">'));

// ------------------------------------------------------------------ helpers
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// Inline markdown → HTML. Order matters: code first so its contents are not
// re-processed, then links, then bold before italic.
function inline(s) {
  let t = esc(s);
  t = t.replace(/`([^`]+)`/g, '<code>$1</code>');
  t = t.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>');
  t = t.replace(/ — /g, ' — ');
  return t;
}

// Strip the unicode-bold characters used for LinkedIn emphasis — they have no
// place in body copy on the site (screen readers read them as symbol soup).
function deBold(s) {
  const map = { 0x1d5d4: 0x41, 0x1d5ee: 0x61, 0x1d5ec: 0x30 };
  return [...s].map(ch => {
    const c = ch.codePointAt(0);
    if (c >= 0x1d5d4 && c <= 0x1d5ed) return String.fromCharCode(c - 0x1d5d4 + 0x41);
    if (c >= 0x1d5ee && c <= 0x1d607) return String.fromCharCode(c - 0x1d5ee + 0x61);
    if (c >= 0x1d7ec && c <= 0x1d7f5) return String.fromCharCode(c - 0x1d7ec + 0x30);
    return ch;
  }).join('');
}

// Stat-band labels are set in uppercase mono, so a full sentence wraps to eight
// lines and wrecks the band. Keep the first clause only.
function shortLabel(s) {
  let t = s.split(' — ')[0].split(/\.\s/)[0].trim();
  if (t.length > 58) t = t.slice(0, 58).replace(/\s+\S*$/, '') + '…';
  return t;
}

// Parse a run of markdown table lines into {head:[], rows:[[]]}.
function parseTable(lines, i) {
  const rows = [];
  while (i < lines.length && /^\s*\|/.test(lines[i])) {
    const cells = lines[i].trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
    if (!/^[-:\s|]+$/.test(cells.join(''))) rows.push(cells);
    i++;
  }
  return { head: rows[0] || [], rows: rows.slice(1), next: i };
}

// ------------------------------------------------------------------ mermaid
// mmdc renders with the render machine's font; rewriting the stack to a
// metrically interchangeable one keeps labels inside their boxes elsewhere.
function renderMermaid(src, id) {
  const inFile = path.join(TMP, `${id}.mmd`);
  const outFile = path.join(TMP, `${id}.svg`);
  const cached = fs.existsSync(outFile) && fs.existsSync(inFile) &&
                 fs.readFileSync(inFile, 'utf8') === src;
  fs.writeFileSync(inFile, src);
  if (cached) return postProcess(fs.readFileSync(outFile, 'utf8'), id);
  // Chromium can't use its sandbox in this environment; mmdc needs the flag
  // passed through a puppeteer config file.
  const pptr = path.join(path.dirname(TMP), 'pptr.json');
  fs.writeFileSync(pptr, '{"args":["--no-sandbox","--disable-setuid-sandbox"]}');
  // Brand palette: cream nodes, orange borders, near-black text — mermaid's
  // default lavender reads as a third-party screenshot on a CapHive page.
  const cfg = path.join(path.dirname(TMP), 'mermaid.json');
  fs.writeFileSync(cfg, JSON.stringify({
    theme: 'base',
    // htmlLabels:false forces native SVG text. With foreignObject labels the
    // box is sized using the render machine's font; the viewer's browser then
    // substitutes a different one and the second line is clipped at the border.
    // It must be set at the ROOT — neither the %%{init}%% directive in the .mmd
    // nor flowchart.htmlLabels here has any effect once -c is passed.
    htmlLabels: false,
    flowchart: { htmlLabels: false, useMaxWidth: true, padding: 12 },
    themeVariables: {
      fontFamily: "Arial,'Liberation Sans',Helvetica,sans-serif",
      fontSize: '15px',
      primaryColor: '#FBF7F1', primaryBorderColor: '#FF4D00', primaryTextColor: '#101010',
      lineColor: '#8A8A8A', secondaryColor: '#F2EFEA', tertiaryColor: '#FFFFFF',
      // sequence diagrams
      actorBkg: '#FBF7F1', actorBorder: '#FF4D00', actorTextColor: '#101010',
      signalColor: '#5A5A5A', signalTextColor: '#101010',
      labelBoxBkgColor: '#FBF7F1', labelBoxBorderColor: '#FF4D00', noteBkgColor: '#FFF3EC',
      noteBorderColor: '#FF4D00'
    }
  }));
  execFileSync('npx', ['--yes', '@mermaid-js/mermaid-cli@11', '-i', inFile, '-o', outFile,
                       '-b', 'transparent', '-w', '1000', '-p', pptr, '-c', cfg], { stdio: 'pipe' });
  return postProcess(fs.readFileSync(outFile, 'utf8'), id);
}

// Unique ids per SVG (several diagrams share one page) and a font stack that is
// metrically interchangeable across machines, so labels stay inside their boxes.
function postProcess(svg, id) {
  svg = svg.replace(/<\?xml[^>]*\?>\s*/, '').replace(/<!DOCTYPE[^>]*>\s*/, '');
  svg = svg.replace(/id="my-svg"/g, `id="${id}"`).replace(/#my-svg/g, `#${id}`);
  svg = svg.replace(/font-family:\s*"?trebuchet ms"?[^;}]*/gi,
                    "font-family:Arial,'Liberation Sans',Helvetica,sans-serif");
  svg = svg.replace(/<svg /, '<svg width="100%" ');
  return svg;
}

// ------------------------------------------------------------- body builder
function buildBody(lines, diagrams) {
  const out = [];
  let di = 0, i = 0;

  while (i < lines.length) {
    const raw = lines[i];
    const line = raw.trim();

    if (!line || line === '---') { i++; continue; }

    // The article's own H1 — the hero already carries the headline.
    if (/^#\s/.test(line)) { i++; continue; }

    // ---- legacy marker style (posts 01–04): content sits inside the marker
    // e.g. **[KEY POINT #1: "…"]**  /  **[STAT BAND: a · b · c]**
    const legacy = line.match(/^\*\*\[([A-Z][A-Z\s#\d]*?):\s*([\s\S]*)\]\*\*$/);
    if (legacy) {
      const kind = legacy[1].trim().replace(/\s*#?\d+$/, '');
      const text = legacy[2].trim().replace(/^"|"$/g, '');

      if (kind === 'KEY POINT' || kind === 'PULL QUOTE') {
        out.push(`<div class="pull"><p>${inline(text)}</p></div>`);
        i++;
        continue;
      }
      if (kind === 'STAT BAND') {
        const items = text.split('·').map(s => s.trim()).filter(Boolean);
        out.push('<div class="stat-band" style="margin:34px 0;border:1px solid var(--line);border-radius:14px;overflow:hidden">' +
          items.map(it => {
            const m = it.match(/^(\S+)\s+([\s\S]*)$/) || [null, it, ''];
            return `<div><strong>${inline(m[1])}</strong><span>${inline(m[2])}</span></div>`;
          }).join('') + '</div>');
        i++;
        continue;
      }
      if (kind === 'DIAGRAM') {
        const d = diagrams[di++];
        if (d) out.push(`<figure style="margin:34px 0"><div style="background:#FFFFFF;border:1px solid var(--line);border-radius:14px;padding:22px;overflow-x:auto">${d}</div></figure>`);
        i++;
        continue;
      }
      // Screenshots we don't have yet, and the CTA panel the site renders
      // globally at the foot of every article, are dropped rather than faked.
      if (/SCREENSHOT|CTA PANEL|IMAGE/.test(kind)) { i++; continue; }
      if (/MOCK|TABLE/.test(kind)) {
        i++;
        while (i < lines.length && !/^\s*\|/.test(lines[i]) && !/^```/.test(lines[i].trim()) && lines[i].trim() === '') i++;
        if (/^\s*\|/.test(lines[i] || '')) {
          const t = parseTable(lines, i); i = t.next;
          out.push(`<figure style="margin:30px 0"><table><thead><tr>${t.head.map(h => `<th>${inline(h)}</th>`).join('')}</tr></thead><tbody>${t.rows.map(r => `<tr>${r.map(c => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table><figcaption style="margin-top:10px;font-size:13px;color:var(--mut)">${inline(text)}</figcaption></figure>`);
        }
        continue;
      }
      i++;
      continue;
    }

    // Stat band: a 3-column table where the header row holds the numbers.
    if (/^\*\*\[STAT BAND\]\*\*/.test(line)) {
      i++;
      while (i < lines.length && !/^\s*\|/.test(lines[i])) i++;
      const t = parseTable(lines, i); i = t.next;
      const labels = t.rows[0] || [];
      out.push('<div class="stat-band" style="margin:34px 0;border:1px solid var(--line);border-radius:14px;overflow:hidden">' +
        t.head.map((n, k) => `<div><strong>${inline(n)}</strong><span>${inline(shortLabel(labels[k] || ""))}</span></div>`).join('') +
        '</div>');
      continue;
    }

    // Key point bands and standalone block quotes both render as a pull quote.
    if (/^\*\*\[KEY POINT/.test(line)) {
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('>')) i++;
      const q = lines[i].trim().replace(/^>\s*/, '').replace(/^\*|\*$/g, '');
      out.push(`<div class="pull"><p>${inline(q)}</p></div>`);
      i++;
      continue;
    }

    // Product mock — a labelled table or code block, always fictional data.
    if (/^\*\*\[MOCK:/.test(line)) {
      const cap = line.replace(/^\*\*\[MOCK:\s*/, '').replace(/\]\*\*$/, '');
      i++;
      while (i < lines.length && !/^\s*\|/.test(lines[i]) && !/^```/.test(lines[i].trim())) i++;
      if (/^```/.test(lines[i]?.trim() || '')) {
        i++;
        const buf = [];
        while (i < lines.length && !/^```/.test(lines[i].trim())) buf.push(lines[i++]);
        i++;
        out.push(`<figure style="margin:30px 0"><pre style="background:var(--bg-2,#F6F4F0);border:1px solid var(--line);border-radius:12px;padding:20px;overflow-x:auto;font-size:13.5px;line-height:1.7">${esc(buf.join('\n'))}</pre><figcaption style="margin-top:10px;font-size:13px;color:var(--mut)">${inline(cap)}</figcaption></figure>`);
      } else {
        const t = parseTable(lines, i); i = t.next;
        out.push(`<figure style="margin:30px 0"><table><thead><tr>${t.head.map(h => `<th>${inline(h)}</th>`).join('')}</tr></thead><tbody>${t.rows.map(r => `<tr>${r.map(c => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table><figcaption style="margin-top:10px;font-size:13px;color:var(--mut)">${inline(cap)}</figcaption></figure>`);
      }
      continue;
    }

    if (/^\*\*\[DIAGRAM/.test(line)) {
      const d = diagrams[di++];
      if (d) {
        out.push(`<figure style="margin:34px 0"><div style="background:#FFFFFF;border:1px solid var(--line);border-radius:14px;padding:22px;overflow-x:auto">${d}</div></figure>`);
      }
      i++;
      continue;
    }

    if (/^\*\*\[COMPARISON TABLE\]\*\*/.test(line)) {
      i++;
      while (i < lines.length && !/^\s*\|/.test(lines[i])) i++;
      const t = parseTable(lines, i); i = t.next;
      out.push(`<table><thead><tr>${t.head.map(h => `<th>${inline(h)}</th>`).join('')}</tr></thead><tbody>${t.rows.map(r => `<tr>${r.map(c => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`);
      continue;
    }

    // A bare table with no marker in front of it.
    if (/^\|/.test(line)) {
      const t = parseTable(lines, i); i = t.next;
      out.push(`<table><thead><tr>${t.head.map(h => `<th>${inline(h)}</th>`).join('')}</tr></thead><tbody>${t.rows.map(r => `<tr>${r.map(c => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`);
      continue;
    }

    // The takeaways block becomes a callout with a numbered list. Accepts both
    // draft conventions: "**1. Bold** rest" and "1. **Bold** rest".
    // Heading styles across drafts: "## ✅ Takeaways", "### ✅ Takeaways",
    // "## Takeaways", and a bare "✅ **Takeaways**" line with no heading marker.
    if (/^##+\s*(✅\s*)?Takeaways/i.test(line) || /^##+\s*✅/.test(line) ||
        /^✅\s*\*{0,2}Takeaways/i.test(line)) {
      i++;
      const items = [];
      while (i < lines.length && !/^(##|———|###)/.test(lines[i].trim()) && !/^---$/.test(lines[i].trim())) {
        const l = lines[i].trim();
        let m = l.match(/^\*\*\d+\.\s*(.+?)\*\*\s*(.*)$/)
             || l.match(/^\d+\.\s*\*\*(.+?)\*\*\s*(.*)$/);
        if (m) items.push(`<li><strong>${inline(m[1])}</strong> ${inline(m[2])}</li>`);
        else if (/^\d+\.\s/.test(l)) items.push(`<li>${inline(l.replace(/^\d+\.\s*/, ''))}</li>`);
        // Once the list has started, the first non-item line ends the block —
        // otherwise the closing question and CTA get swallowed into it.
        else if (items.length && l) break;
        i++;
      }
      out.push(`<h2>What to take from this</h2><div class="callout"><ol>${items.join('')}</ol></div>`);
      continue;
    }

    // The demo CTA panel that closes every piece.
    if (/^###\s*💡/.test(line)) {
      i++;
      const buf = [];
      while (i < lines.length && !/^(##|---)/.test(lines[i].trim())) {
        const l = lines[i].trim();
        if (l) buf.push(l);
        i++;
      }
      const q = buf.filter(b => /^\*\*Question/.test(b)).map(b => inline(b.replace(/^\*\*|\*\*$/g, '')));
      const body = buf.filter(b => !/^\*\*Question/.test(b)).map(b => `<p>${inline(b)}</p>`).join('');
      out.push(`<h2>See it on your own structure</h2>${body}` +
        (q.length ? `<div class="callout"><p>${q.join(' ')}</p></div>` : ''));
      continue;
    }

    if (/^##\s/.test(line)) { out.push(`<h2>${inline(line.replace(/^##\s*/, ''))}</h2>`); i++; continue; }
    if (/^###\s/.test(line)) { out.push(`<h3>${inline(line.replace(/^###\s*/, ''))}</h3>`); i++; continue; }
    if (/^———$/.test(line) || /^• • •$/.test(line)) { i++; continue; }

    // Standalone block quote → pull quote.
    if (/^>\s/.test(line)) {
      const q = line.replace(/^>\s*/, '').replace(/^\*|\*$/g, '');
      out.push(`<div class="pull"><p>${inline(q)}</p></div>`);
      i++;
      continue;
    }

    // Ordered list (used for the trigger-shape and agent frameworks).
    if (/^\d+\.\s/.test(line)) {
      const items = [];
      while (i < lines.length && /^\d+\.\s/.test(lines[i].trim())) {
        items.push(`<li>${inline(lines[i].trim().replace(/^\d+\.\s*/, ''))}</li>`);
        i++;
      }
      out.push(`<ol>${items.join('')}</ol>`);
      continue;
    }

    if (/^-\s/.test(line)) {
      const items = [];
      while (i < lines.length && /^-\s/.test(lines[i].trim())) {
        items.push(`<li>${inline(lines[i].trim().replace(/^-\s*/, ''))}</li>`);
        i++;
      }
      out.push(`<ul>${items.join('')}</ul>`);
      continue;
    }

    // Fenced code (the data-room folder tree).
    if (/^```/.test(line)) {
      i++;
      const buf = [];
      while (i < lines.length && !/^```/.test(lines[i].trim())) buf.push(lines[i++]);
      i++;
      out.push(`<pre style="background:var(--bg-2,#F6F4F0);border:1px solid var(--line);border-radius:12px;padding:20px;overflow-x:auto;font-size:13.5px;line-height:1.7">${esc(buf.join('\n'))}</pre>`);
      continue;
    }

    // Everything else is a paragraph; a bold-only line becomes a lead-in.
    out.push(`<p>${inline(line)}</p>`);
    i++;
  }
  return { html: out.join('\n        '), used: di };
}

// Drafts written for LinkedIn keep their diagram in a trailing section rather
// than inline, so any diagram no marker claimed is placed just above "The
// impact" — the point in every piece where the mechanism has just been
// explained and a picture of it is worth most.
function placeLeftovers(html, diagrams, used) {
  const rest = diagrams.slice(used);
  if (!rest.length) return html;
  const figs = rest.map(d =>
    `<figure style="margin:34px 0"><div style="background:#FFFFFF;border:1px solid var(--line);border-radius:14px;padding:22px;overflow-x:auto">${d}</div></figure>`).join('\n        ');
  const at = html.search(/<h2>[^<]*(📊|The impact)/);
  return at > -1 ? html.slice(0, at) + figs + '\n        ' + html.slice(at) : html + '\n        ' + figs;
}

// ------------------------------------------------------------------- render
// SITE.md requires measured reading times, not estimates: 225 wpm over the
// rendered body text.
function readTime(html) {
  const words = html.replace(/<svg[\s\S]*?<\/svg>/g, ' ')
                    .replace(/<[^>]+>/g, ' ')
                    .split(/\s+/).filter(Boolean).length;
  return `${Math.max(1, Math.round(words / 225))} min read`;
}

function page(p, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(p.crumb)} | CapHive</title>
<meta name="description" content="${esc(p.desc)}">
<meta name="theme-color" content="#FBFAF7">
<link rel="canonical" href="https://caphive.com/${p.slug}.html">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 30 34'%3E%3Cpath d='M15 1L29 9v16L15 33 1 25V9L15 1z' fill='none' stroke='%23FF4D00' stroke-width='3'/%3E%3Cpath d='M15 9l7 4v8l-7 4-7-4v-8l7-4z' fill='%23FF4D00'/%3E%3C/svg%3E">
<meta property="og:title" content="${esc(p.crumb)}">
<meta property="og:description" content="${esc(p.desc)}">
<meta property="og:type" content="article">
<meta property="og:url" content="https://caphive.com/${p.slug}.html">
<meta property="og:image" content="https://caphive.com/og.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700;800&family=Geist+Mono:wght@400;500;600&family=Instrument+Serif:ital@0;1&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/css/caphive.css?v=a548770e">
</head>
<body data-page="resources">

${NAV}<article>
  <!-- ================= ARTICLE HERO ================= -->
  <header class="page-hero article-hero hero-tinted ${p.tint}">
    <div class="wrap">
      <div class="hero-panel">
        <div class="article-measure">
          <nav class="crumbs" aria-label="Breadcrumb">
            <a href="index.html">Home</a><span>/</span><a href="blog.html">Insights</a><span>/</span>${esc(p.crumb)}
          </nav>
          <span class="chip-label">${esc(p.chip)}</span>
          <h1 style="margin-top:22px">${p.h1}</h1>
          <p class="lede">${esc(p.desc)}</p>
          <div class="article-meta">
            <time datetime="${DATE}">${DATE_LABEL}</time>
            <span class="dot">·</span>
            <span>${readTime(body)}</span>
            <span class="dot">·</span>
            <span>${esc(p.chip)}</span>
          </div>
        </div>
      </div>
    </div>
  </header>

  <!-- ================= ARTICLE BODY ================= -->
  <div class="article-body">
    <div class="wrap">
      <div class="article-card">
        <div class="article-measure">
          <div class="prose">
        ${body}
          </div>
        </div>
      </div>
    </div>
  </div>
</article>

${FOOT}<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BlogPosting",
  "headline": ${JSON.stringify(p.crumb)},
  "description": ${JSON.stringify(p.desc)},
  "datePublished": "${DATE}",
  "author": { "@type": "Organization", "name": "CapHive" },
  "publisher": { "@type": "Organization", "name": "CapHive" },
  "mainEntityOfPage": "https://caphive.com/${p.slug}.html"
}
</script>
</body>
</html>
`;
}

// --------------------------------------------------------------------- main
for (const p of POSTS) {
  const md = fs.readFileSync(path.join(SRC, p.md), 'utf8');

  const mermaids = [...md.matchAll(/```mermaid\n([\s\S]*?)```/g)].map(m => m[1]);
  const diagrams = mermaids.map((src, k) => {
    try { return renderMermaid(src, `svg-${p.slug}-${k}`); }
    catch (e) { console.error(`  ! diagram ${k} failed for ${p.slug}: ${e.message.slice(0, 120)}`); return null; }
  }).filter(Boolean);

  // Body is the span between the post's declared start/end headings.
  const startMark = p.bodyStart || '\n## Article\n';
  const endMark = p.bodyEnd || '\n## Mermaid diagram';
  const s = md.indexOf(startMark);
  const e = md.indexOf(endMark, s + startMark.length);
  if (s < 0 || e < 0) { console.error(`  ! body markers not found in ${p.md}`); continue; }
  // Skip past the rest of the start heading's line (some say "## Article body (source…)").
  const from = md.indexOf('\n', s + 4) + 1;
  const bodyMd = deBold(md.slice(from, e));
  const built = buildBody(bodyMd.split('\n'), diagrams);
  const body = placeLeftovers(built.html, diagrams, built.used);

  fs.writeFileSync(path.join(OUT, `${p.slug}.html`), page(p, body));
  console.log(`✓ ${p.slug}.html  (${diagrams.length} diagram${diagrams.length === 1 ? '' : 's'}, ${built.used} inline)`);
}

// ------------------------------------------------- blog index + sitemap
const cardSvg = '<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M3 8h10M9 4l4 4-4 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const cards = POSTS.map(p => `      <a class="article" href="${p.slug}.html">
        <time datetime="${DATE}">${DATE_LABEL}</time>
        <div>
          <h3>${esc(p.crumb === 'The LP CRM' ? 'Your CRM ends at “Committed.” That’s where the work starts' : p.h1.replace(/<\/?em>/g, ''))}</h3>
          <p>${esc(p.card)}</p>
        </div>
        <span class="go">${cardSvg}</span>
      </a>`).join('\n');

let blog = fs.readFileSync(path.join(OUT, 'blog.html'), 'utf8');
const anchor = '      <a class="article" href="ai-is-ready.html">';
if (!blog.includes('side-letter-obligations.html')) {
  blog = blog.replace(anchor, cards + '\n' + anchor);
  fs.writeFileSync(path.join(OUT, 'blog.html'), blog);
  console.log('✓ blog.html — 9 cards inserted');
} else {
  console.log('· blog.html already contains the new cards, left alone');
}

let sm = fs.readFileSync(path.join(OUT, 'sitemap.xml'), 'utf8');
const entries = POSTS.filter(p => !sm.includes(`${p.slug}.html`)).map(p =>
  `  <url><loc>https://caphive.com/${p.slug}.html</loc><lastmod>${DATE}</lastmod><changefreq>monthly</changefreq><priority>0.6</priority></url>`).join('\n');
if (entries) {
  sm = sm.replace('</urlset>', entries + '\n</urlset>');
  fs.writeFileSync(path.join(OUT, 'sitemap.xml'), sm);
  console.log('✓ sitemap.xml updated');
}
