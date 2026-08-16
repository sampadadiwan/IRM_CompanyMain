/* ============================================================
   CapHive — shared page behaviour
   Progressive enhancement only: every page must read fine
   with JavaScript disabled.
   ============================================================ */
(function(){
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var finePointer = window.matchMedia('(pointer: fine)').matches;

  /* ---- nav shadow on scroll ---- */
  var nav = document.getElementById('nav');
  if(nav){
    var onScroll = function(){ nav.classList.toggle('scrolled', window.scrollY > 24); };
    window.addEventListener('scroll', onScroll, {passive:true});
    onScroll();
  }

  /* ---- mobile menu ---- */
  var toggle = document.getElementById('navToggle');
  var menu = document.getElementById('mobileMenu');
  if(toggle && menu){
    toggle.addEventListener('click', function(){
      var open = menu.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open);
      document.body.style.overflow = open ? 'hidden' : '';
    });
    menu.querySelectorAll('a').forEach(function(a){
      a.addEventListener('click', function(){
        menu.classList.remove('open');
        toggle.setAttribute('aria-expanded','false');
        document.body.style.overflow = '';
      });
    });
    document.addEventListener('keydown', function(e){
      if(e.key === 'Escape' && menu.classList.contains('open')){
        menu.classList.remove('open');
        toggle.setAttribute('aria-expanded','false');
        document.body.style.overflow = '';
      }
    });
  }

  /* ---- mark the current page in the nav ----
     Each page sets <body data-page="products"> and nav links carry
     data-nav="products". Pages that live under a top-level nav item highlight
     their parent, so a visitor on funds.html still sees "Products" lit. */
  var NAV_PARENT = {
    funds:'products', portfolios:'products', deals:'products',
    'ai-agents':'products', integrations:'products',
    pricing:'solutions',
    cases:'resources', faq:'resources', security:'resources'
  };
  var page = document.body.dataset.page;
  if(page){
    [page, NAV_PARENT[page]].forEach(function(key, i){
      if(!key) return;
      document.querySelectorAll('[data-nav="' + key + '"]').forEach(function(el){
        el.classList.add('active');
        if(i === 0 && el.tagName === 'A') el.setAttribute('aria-current','page');
      });
    });
  }

  /* ---- login: send the visitor to the app on their own domain ----
     The markup ships https://app.caphive.com/ so the link works with JavaScript
     off. On a recognised regional domain this swaps in that region's app host,
     matched against an allowlist rather than by prefixing "app." to whatever
     hostname we happen to be on — otherwise localhost and preview deploys would
     produce links to hosts that do not exist.
     The footer's "Login — IND" / "Login — USA" links are deliberately pinned per
     region and carry no data-login, so they are left alone. */
  var APP_BY_DOMAIN = {
    'caphive.com': 'https://app.caphive.com/',
    'caphive.us':  'https://app.caphive.us/'
  };
  var appUrl = APP_BY_DOMAIN[location.hostname.replace(/^www\./, '')];
  if(appUrl){
    document.querySelectorAll('a[data-login]').forEach(function(a){ a.href = appUrl; });
  }

  /* ---- footer year ---- */
  document.querySelectorAll('[data-year]').forEach(function(el){
    el.textContent = new Date().getFullYear();
  });

  /* ---- duplicate any marquee track so the loop is seamless ---- */
  document.querySelectorAll('[data-dup]').forEach(function(el){ el.innerHTML += el.innerHTML; });

  /* ---- scroll reveal (blur-fade) ---- */
  var revealables = document.querySelectorAll('.reveal');
  if(revealables.length && 'IntersectionObserver' in window){
    var io = new IntersectionObserver(function(entries){
      entries.forEach(function(e){
        if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, {threshold:0.12, rootMargin:'0px 0px -40px 0px'});
    revealables.forEach(function(el){ io.observe(el); });
  } else {
    revealables.forEach(function(el){ el.classList.add('in'); });
  }

  /* ---- odometer metrics ---- */
  function buildOdo(el){
    var str = Number(el.dataset.value).toLocaleString('en-US');
    el.textContent = '';
    str.split('').forEach(function(ch){
      if(ch >= '0' && ch <= '9'){
        var d = document.createElement('span'); d.className = 'odo-digit';
        var reel = document.createElement('span'); reel.className = 'odo-reel';
        reel.dataset.digit = ch;
        for(var k = 0; k < 10; k++){
          var s = document.createElement('span'); s.textContent = k; reel.appendChild(s);
        }
        d.appendChild(reel); el.appendChild(d);
      } else {
        var sep = document.createElement('span'); sep.textContent = ch; el.appendChild(sep);
      }
    });
  }
  var odos = [].slice.call(document.querySelectorAll('.odo'));
  if(odos.length && 'IntersectionObserver' in window){
    odos.forEach(buildOdo);
    var oio = new IntersectionObserver(function(entries){
      entries.forEach(function(e){
        if(!e.isIntersecting) return;
        oio.unobserve(e.target);
        e.target.querySelectorAll('.odo-reel').forEach(function(r, i){
          r.style.transitionDelay = (i * 110) + 'ms';
          requestAnimationFrame(function(){
            r.style.transform = 'translateY(-' + r.dataset.digit + 'em)';
          });
        });
      });
    }, {threshold:0.6});
    odos.forEach(function(el){ oio.observe(el); });
  }

  /* ---- magnetic primary buttons ---- */
  if(finePointer && !reduced){
    [].slice.call(document.querySelectorAll('.btn-primary, .btn-white, .btn-dark')).forEach(function(b){
      b.addEventListener('mousemove', function(e){
        var r = b.getBoundingClientRect();
        var mx = (e.clientX - r.left - r.width/2) * 0.22;
        var my = (e.clientY - r.top - r.height/2) * 0.35;
        b.style.transform = 'translate(' + mx + 'px,' + my + 'px)';
      });
      b.addEventListener('mouseleave', function(){ b.style.transform = ''; });
    });
  }

  /* ---- generic tabs ----
     <div data-tabs>
       <button class="tab" data-tab="a">…</button>
       <div class="panel" data-panel="a">…</div>
     </div> */
  document.querySelectorAll('[data-tabs]').forEach(function(root){
    var tabs = [].slice.call(root.querySelectorAll('[data-tab]'));
    var panels = [].slice.call(root.querySelectorAll('[data-panel]'));
    tabs.forEach(function(t){
      t.addEventListener('click', function(){
        tabs.forEach(function(x){
          var on = x === t;
          x.classList.toggle('active', on);
          x.setAttribute('aria-selected', on);
        });
        panels.forEach(function(p){ p.classList.toggle('active', p.dataset.panel === t.dataset.tab); });
      });
    });
  });

  /* ---- FAQ: only one open at a time inside a .faq group ---- */
  document.querySelectorAll('.faq').forEach(function(group){
    var items = [].slice.call(group.querySelectorAll('details'));
    items.forEach(function(d){
      d.addEventListener('toggle', function(){
        if(d.open) items.forEach(function(o){ if(o !== d) o.open = false; });
      });
    });
  });

  /* ============================================================
     CONVERSION PATH
     The demo form and the events that measure it.
     See docs/technical/website_lead_capture.md.
     ============================================================ */
  var CFG = window.CAPHIVE || {};
  /* caphiveTrack is defined by _partials/analytics.html. Stubbed so this file
     stays safe on any page rendered without that partial. */
  var track = window.caphiveTrack || function(){};

  /* ---- forms ----
     Two modes, chosen by whether site_config resolved an endpoint for this host:

       POST mode   the real path. FormData is posted to our own /website_leads
                   endpoint on the app host and the browser is sent to the
                   thank-you page, which is what gives the conversion its own
                   URL. A lead is recorded whether or not the visitor follows
                   through in a second application.
       mailto mode the original behaviour, kept ONLY as the fallback for a host
                   site_config does not recognise, so the form never silently
                   swallows a lead.

     <form data-mailto="…"> still marks a form as ours; data-subject still sets
     the mail subject in fallback mode.
  */
  document.querySelectorAll('form[data-mailto], form[data-endpoint]').forEach(function(form){
    /* Per-form override beats the global, so a second form (say a gated
       download) can post elsewhere without touching this file. */
    var endpoint = form.dataset.endpoint || CFG.formEndpoint || '';
    var msg = form.querySelector('.form-msg');
    var btn = form.querySelector('button[type="submit"], button:not([type])');

    /* Stamp when the page rendered, for the server's time-to-submit check. Done
       here rather than in the markup so a page served from cache carries a fresh
       value — a stale stamp would make every cached-page submission look slow,
       which is harmless, but a stamp baked into the HTML by the build would be
       months old and tell us nothing at all. */
    var ts = form.querySelector('input[name="_ts"]');
    if(ts) ts.value = String(Date.now());

    /* The static copy in the markup describes mailto mode, because that is what
       the page does until an endpoint resolves. Once one does, correct it —
       leaving "your email client is opening" on a form that posts server-side is
       a lie the visitor can see. */
    if(endpoint){
      if(msg) msg.textContent = 'Sending your request…';
      /* Hide only the mail-client sentence. The rest of the note, including the
         Privacy Policy link, must survive: a real submission records an IP. */
      form.querySelectorAll('[data-mailto-only]').forEach(function(el){
        el.hidden = true;
        el.style.display = 'none';
      });
    }

    form.addEventListener('submit', function(e){
      e.preventDefault();

      /* ---- fallback: compose in the visitor's own mail client ---- */
      if(!endpoint){
        var to = form.dataset.mailto;
        var subject = form.dataset.subject || 'Website enquiry';
        var lines = [];
        new FormData(form).forEach(function(v, k){
          /* Underscore-prefixed keys are plumbing (_hp, _ts) and have no place
             in an email a human reads. */
          if(String(v).trim() !== '' && k.charAt(0) !== '_') lines.push(k.charAt(0).toUpperCase() + k.slice(1) + ': ' + v);
        });
        var firmEl = form.querySelector('[name="firm"]');
        if(firmEl && firmEl.value) subject += ' — ' + firmEl.value;
        if(msg) msg.classList.add('show');
        location.href = 'mailto:' + to +
          '?subject=' + encodeURIComponent(subject) +
          '&body=' + encodeURIComponent(lines.join('\n'));
        return;
      }

      /* ---- POST mode ---- */
      var data = new FormData(form);
      /* Which page produced the lead. The published articles are the outbound
         proof assets, so knowing which ones convert directs future writing. */
      data.append('_source_page', location.pathname.replace(/^.*\//, '') || 'index.html');
      /* Carry the campaign through, so a reply can be attributed to the sequence
         that produced it. */
      var qs = new URLSearchParams(location.search);
      ['utm_source','utm_medium','utm_campaign','utm_content','utm_term'].forEach(function(k){
        if(qs.get(k)) data.append(k, qs.get(k));
      });

      if(btn){ btn.disabled = true; btn.setAttribute('aria-busy','true'); }
      if(msg) msg.classList.add('show');

      /* No credentials, and only CORS-safelisted headers, which keeps this a
         simple request with no preflight. The endpoint is unauthenticated by
         design — do not add a custom header without checking that the OPTIONS
         route still answers. */
      fetch(endpoint, {
        method: 'POST',
        body: data,
        headers: { 'Accept': 'application/json' }
      }).then(function(res){
        if(!res.ok) throw new Error('HTTP ' + res.status);
        /* Fired here AND inferred from the thank-you URL below — a redirect can
           cut a beacon short, so the landing page is the reliable signal and this
           is the belt to its braces. No PII in the params. */
        track('demo_form_submitted', { form_id: form.id || 'demo', method: 'post' });
        var dest = CFG.thankYouUrl || 'thank-you.html';
        location.href = dest + (dest.indexOf('?') === -1 ? '?' : '&') + 'src=demo-form';
      }).catch(function(err){
        if(btn){ btn.disabled = false; btn.removeAttribute('aria-busy'); }
        /* Never lose the lead to a network error: say so plainly and give the
           visitor a route that does not depend on us. */
        if(msg){
          msg.classList.add('show');
          msg.textContent = 'That did not send — please email hello@CapHive.com directly and we will pick it up.';
        }
        if(window.console) console.error('form submit failed', err);
      });
    });
  });

  /* ---- conversion event on the landing page ----
     thank-you.html?src=demo-form -> demo_form_submitted
     Gated on the query param so a direct visit or a bookmark never fires a false
     conversion. */
  (function(){
    if(new URLSearchParams(location.search).get('src') === 'demo-form'){
      track('demo_form_submitted', { method: 'thankyou_page' });
    }
  }());

  /* ---- rotating proof line: <div data-rotate='["a","b"]'> ---- */
  document.querySelectorAll('[data-rotate]').forEach(function(el){
    if(reduced) return;
    var items;
    try { items = JSON.parse(el.dataset.rotate); } catch(err){ return; }
    if(!items || items.length < 2) return;
    var i = 0;
    setInterval(function(){
      i = (i + 1) % items.length;
      el.classList.add('fade');
      setTimeout(function(){ el.textContent = items[i]; el.classList.remove('fade'); }, 300);
    }, 3400);
  });

  /* ---- live-ish number ticker: <span data-tick="412386905" data-prefix="US$ "> ---- */
  document.querySelectorAll('[data-tick]').forEach(function(el){
    if(reduced) return;
    var v = Number(el.dataset.tick);
    var prefix = el.dataset.prefix || '';
    setInterval(function(){
      v += 1200 + Math.floor(Math.random() * 8600);
      el.textContent = prefix + v.toLocaleString('en-US');
    }, 2600);
  });
})();
