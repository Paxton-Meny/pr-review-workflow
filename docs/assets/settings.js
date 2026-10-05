/*
 * Behaviour for the settings reference. No dependencies.
 *
 * The page is complete without this file: every entry shows its default
 * state as static markup. This script only adds the switching, the
 * sidebar filter, the glossary tips, the current-section markers, and
 * the phone menu. It writes text with textContent, never markup, and
 * reads nothing from the URL, storage, or the network.
 */
(function () {
  'use strict';

  var doc = document;

  function all(selector, root) {
    return Array.prototype.slice.call((root || doc).querySelectorAll(selector));
  }

  function tokens(el, name) {
    var value = el.getAttribute(name);
    return value ? value.split(' ') : [];
  }

  function press(buttons, value) {
    buttons.forEach(function (button) {
      button.setAttribute('aria-pressed', String(button.getAttribute('data-set') === value));
    });
  }

  /* Reveal a control bar that is hidden while the page is static. */
  function reveal(unit) {
    all('.unit-bar, .ctl-row', unit).forEach(function (bar) {
      bar.hidden = false;
    });
  }

  /*
   * One-value switchers. Inside a [data-switch] unit, an element with
   * data-show="a b" is visible for values a and b, and an element with
   * data-on="a b" carries the class is-on for them.
   */
  function applySwitch(unit, value) {
    press(all('[data-set]', unit), value);
    all('[data-show]', unit).forEach(function (el) {
      el.hidden = tokens(el, 'data-show').indexOf(value) === -1;
    });
    all('[data-on]', unit).forEach(function (el) {
      el.classList.toggle('is-on', tokens(el, 'data-on').indexOf(value) !== -1);
    });
  }

  function initSwitches() {
    all('[data-switch]').forEach(function (unit) {
      reveal(unit);
      unit.addEventListener('click', function (event) {
        var button = event.target.closest('[data-set]');
        if (button && unit.contains(button)) {
          applySwitch(unit, button.getAttribute('data-set'));
        }
      });
    });
  }

  /*
   * The model explainer: four choices combine into one answer per role.
   * The rules mirror the review skill's routing; the settings test in
   * the repository pins the thresholds this text quotes.
   */
  var TIERS = {
    low: { label: 'sonnet', cls: 'pill pill-low' },
    base: { label: 'session model', cls: 'pill' },
    high: { label: 'opus', cls: 'pill pill-high' }
  };

  function route(state) {
    var auto = state.routing === 'auto';
    var strong = state.strong === 'opus';
    var verifier = state.verifier === 'sonnet' ? 'low' : 'base';
    var reviewer = 'base';
    var reviewerWhy = 'Nothing about this change routes it up or down.';
    var lowered = false;

    if (!auto) {
      reviewerWhy = 'Fixed: always the reviewer model you set.';
    } else if (state.change === 'docs') {
      reviewer = 'low';
      lowered = true;
      reviewerWhy = 'A small docs-only change with no risk signal is mechanical work.';
    } else if (state.change === 'large' || state.change === 'auth') {
      var reason = state.change === 'large' ? 'Over 800 lines of code.' : 'Touches a sensitive surface.';
      reviewer = strong ? 'high' : 'base';
      reviewerWhy = strong
        ? reason + ' Routing climbs to the strong model.'
        : reason + ' No strong model is set, so routing stops at the reviewer model.';
    }

    var fixedVerifier = 'Always the verifier model. Routing never changes it.';
    return {
      reviewer: { tier: reviewer, why: reviewerWhy },
      gap: {
        tier: lowered ? 'base' : reviewer,
        why: lowered
          ? 'The safety net follows the reviewer up, never down.'
          : 'Same as the reviewer, when a gap pass runs.'
      },
      filter: { tier: verifier, why: fixedVerifier },
      editor: {
        tier: 'base',
        why: auto
          ? 'Drops to sonnet only in round one, when every open finding is minor and carries a proven suggestion.'
          : 'Fixed: always the editor model you set.'
      },
      verifier: { tier: verifier, why: fixedVerifier }
    };
  }

  function initRouting() {
    var unit = doc.querySelector('[data-routing]');
    if (!unit) {
      return;
    }
    var groups = all('[data-group]', unit);
    var state = {};

    function render() {
      var result = route(state);
      Object.keys(result).forEach(function (role) {
        var pill = unit.querySelector('[data-model="' + role + '"]');
        var why = unit.querySelector('[data-why="' + role + '"]');
        var tier = TIERS[result[role].tier];
        if (pill && why && tier) {
          pill.textContent = tier.label;
          pill.className = tier.cls;
          why.textContent = result[role].why;
        }
      });
    }

    groups.forEach(function (group) {
      var name = group.getAttribute('data-group');
      var buttons = all('[data-set]', group);
      var current = buttons.filter(function (button) {
        return button.getAttribute('aria-pressed') === 'true';
      })[0];
      state[name] = current ? current.getAttribute('data-set') : '';
      group.addEventListener('click', function (event) {
        var button = event.target.closest('[data-set]');
        if (button && group.contains(button)) {
          state[name] = button.getAttribute('data-set');
          press(buttons, state[name]);
          render();
        }
      });
    });

    reveal(unit);
    render();
  }

  /* The sidebar filter narrows the list of settings as you type. */
  function initFilter() {
    var input = doc.getElementById('filter');
    var nav = doc.getElementById('settings-nav');
    var none = doc.getElementById('filter-none');
    if (!input || !nav || !none) {
      return;
    }
    var groups = all('.side-group', nav);

    function matches(link, words) {
      var hay = (link.textContent + ' ' + (link.getAttribute('data-words') || '')).toLowerCase();
      return words.every(function (word) {
        return hay.indexOf(word) !== -1;
      });
    }

    function apply() {
      var words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      var shown = 0;
      groups.forEach(function (group) {
        var visible = 0;
        all('a', group).forEach(function (link) {
          var hit = matches(link, words);
          link.hidden = !hit;
          visible += hit ? 1 : 0;
        });
        group.hidden = visible === 0;
        shown += visible;
      });
      none.hidden = shown !== 0;
    }

    input.addEventListener('input', apply);
    input.addEventListener('keydown', function (event) {
      if (event.key === 'Enter') {
        var first = all('a', nav).filter(function (link) {
          return !link.hidden;
        })[0];
        if (first) {
          first.click();
        }
      } else if (event.key === 'Escape') {
        input.value = '';
        apply();
      }
    });
  }

  /* Glossary terms show their definition on hover and on focus. */
  function initTips() {
    var tip = doc.createElement('div');
    tip.className = 'tip';
    tip.id = 'tip';
    tip.setAttribute('role', 'tooltip');
    tip.hidden = true;
    doc.body.appendChild(tip);
    var owner = null;

    function hide() {
      if (owner) {
        owner.removeAttribute('aria-describedby');
        owner = null;
      }
      tip.hidden = true;
    }

    function show(term) {
      var target = doc.getElementById((term.getAttribute('href') || '').slice(1));
      var definition = target && target.querySelector('dd');
      if (!definition) {
        return;
      }
      tip.textContent = definition.textContent;
      tip.hidden = false;
      var box = term.getBoundingClientRect();
      var width = tip.offsetWidth;
      var left = Math.max(8, Math.min(box.left, doc.documentElement.clientWidth - width - 8));
      var above = box.top - tip.offsetHeight - 8;
      tip.style.left = left + window.pageXOffset + 'px';
      tip.style.top = (above > 8 ? above : box.bottom + 8) + window.pageYOffset + 'px';
      owner = term;
      term.setAttribute('aria-describedby', 'tip');
    }

    all('a.term').forEach(function (term) {
      term.addEventListener('mouseenter', function () { show(term); });
      term.addEventListener('focus', function () { show(term); });
      term.addEventListener('mouseleave', hide);
      term.addEventListener('blur', hide);
    });
    doc.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') {
        hide();
      }
    });
    window.addEventListener('scroll', hide, { passive: true });
  }

  /* Mark the section being read in the sidebar and the outline. */
  function initSpy() {
    var sets = [all('#settings-nav a'), all('.rail a')].map(function (links) {
      return links.map(function (link) {
        return { link: link, target: doc.getElementById((link.getAttribute('href') || '').slice(1)) };
      }).filter(function (pair) {
        return pair.target;
      });
    });
    var queued = false;

    /* The current section is the last one whose top has passed the bar. */
    function mark() {
      queued = false;
      sets.forEach(function (pairs) {
        var current = null;
        pairs.forEach(function (pair) {
          pair.link.removeAttribute('aria-current');
          if (pair.target.getBoundingClientRect().top <= 120) {
            current = pair;
          }
        });
        if (current) {
          current.link.setAttribute('aria-current', 'true');
        }
      });
    }

    window.addEventListener('scroll', function () {
      if (!queued) {
        queued = true;
        window.requestAnimationFrame(mark);
      }
    }, { passive: true });
    mark();
  }

  /* On a phone the list of settings sits behind a menu button. */
  function initMenu() {
    var button = doc.getElementById('menu');
    var nav = doc.getElementById('settings-nav');
    if (!button || !nav) {
      return;
    }
    function set(open) {
      nav.classList.toggle('open', open);
      button.setAttribute('aria-expanded', String(open));
    }
    button.addEventListener('click', function () {
      set(!nav.classList.contains('open'));
    });
    nav.addEventListener('click', function (event) {
      if (event.target.closest('a')) {
        set(false);
      }
    });
  }

  doc.documentElement.classList.add('js');
  initSwitches();
  initRouting();
  initFilter();
  initTips();
  initSpy();
  initMenu();
}());
