var LiveView = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var __async = (__this, __arguments, generator) => {
    return new Promise((resolve, reject) => {
      var fulfilled = (value) => {
        try {
          step(generator.next(value));
        } catch (e) {
          reject(e);
        }
      };
      var rejected = (value) => {
        try {
          step(generator.throw(value));
        } catch (e) {
          reject(e);
        }
      };
      var step = (x) => x.done ? resolve(x.value) : Promise.resolve(x.value).then(fulfilled, rejected);
      step((generator = generator.apply(__this, __arguments)).next());
    });
  };

  // js/backpex.js
  var backpex_exports = {};
  __export(backpex_exports, {
    Hooks: () => hooks_exports
  });

  // js/hooks/index.js
  var hooks_exports = {};
  __export(hooks_exports, {
    BackpexCancelEntry: () => cancel_entry_default,
    BackpexDragHover: () => drag_hover_default,
    BackpexSidebarSections: () => sidebar_sections_default,
    BackpexStickyActions: () => sticky_actions_default,
    BackpexThemeSelector: () => theme_selector_default,
    BackpexTooltip: () => tooltip_default
  });

  // js/hooks/_cancel_entry.js
  var cancel_entry_default = {
    mounted() {
      this.form = this.el.closest("form");
      const uploadKey = this.el.dataset.uploadKey;
      this.handleEvent(`cancel-entry:${uploadKey}`, (e) => {
        this.dispatchChangeEvent();
      });
      this.handleEvent(`cancel-existing-entry:${uploadKey}`, (e) => {
        this.dispatchChangeEvent();
      });
    },
    dispatchChangeEvent() {
      if (this.form) {
        this.el.dispatchEvent(new Event("input", { bubbles: true }));
      }
    }
  };

  // js/hooks/_drag_hover.js
  var drag_hover_default = {
    mounted() {
      this.dragging = 0;
      this.controller = new AbortController();
      const signal = this.controller.signal;
      this.el.addEventListener("dragenter", () => this.dragChange(this.dragging + 1), { signal });
      this.el.addEventListener("dragleave", () => this.dragChange(this.dragging - 1), { signal });
      this.el.addEventListener("drop", () => this.dragChange(0), { signal });
    },
    destroyed() {
      this.controller.abort();
    },
    dragChange(value) {
      this.dragging = value;
      this.el.firstElementChild.classList.toggle("border-primary", this.dragging > 0);
    }
  };

  // js/hooks/_sidebar_sections.js
  var sidebar_sections_default = {
    mounted() {
      this.initializeSections();
    },
    updated() {
      this.initializeSections();
    },
    destroyed() {
      const sections = this.el.querySelectorAll("[data-section-id]");
      sections.forEach((section) => {
        const toggle = section.querySelector("[data-menu-dropdown-toggle]");
        toggle.removeEventListener("click", this.handleToggle.bind(this));
      });
    },
    hasContent(element) {
      if (!element || element.children.length === 0) {
        return false;
      }
      for (const child of element.children) {
        const childContent = child.querySelector("[data-menu-dropdown-content]");
        if (childContent) {
          if (this.hasContent(childContent)) {
            return true;
          }
        } else {
          return true;
        }
      }
      return false;
    },
    initializeSections() {
      const sections = this.el.querySelectorAll("[data-section-id]");
      sections.forEach((section) => {
        const sectionId = section.dataset.sectionId;
        const toggle = section.querySelector("[data-menu-dropdown-toggle]");
        const content = section.querySelector("[data-menu-dropdown-content]");
        if (!this.hasContent(content)) {
          content.style.display = "none";
          return;
        }
        const isOpen = localStorage.getItem(`sidebar-section-${sectionId}`) === "true";
        if (!isOpen) {
          toggle.classList.remove("menu-dropdown-show");
          content.style.display = "none";
        }
        section.classList.remove("hidden");
        toggle.addEventListener("click", this.handleToggle.bind(this));
      });
    },
    handleToggle(event) {
      const section = event.currentTarget.closest("[data-section-id]");
      const sectionId = section.dataset.sectionId;
      const toggle = section.querySelector("[data-menu-dropdown-toggle]");
      const content = section.querySelector("[data-menu-dropdown-content]");
      toggle.classList.toggle("menu-dropdown-show");
      content.style.display = content.style.display === "none" ? "block" : "none";
      const isNowOpen = toggle.classList.contains("menu-dropdown-show");
      localStorage.setItem(`sidebar-section-${sectionId}`, isNowOpen);
    }
  };

  // js/hooks/_sticky_actions.js
  var sticky_actions_default = {
    mounted() {
      this.sticky = this.el.querySelector(".sticky");
      this.observer = new IntersectionObserver(
        ([entry]) => {
          this.stuck = entry.intersectionRatio < 1;
          this.toggleStuckAttribute();
        },
        { threshold: [1], root: this.el.closest(".overflow-x-auto") }
      );
      this.observer.observe(this.el);
    },
    updated() {
      this.toggleStuckAttribute();
    },
    destroyed() {
      this.observer.disconnect();
    },
    toggleStuckAttribute() {
      this.sticky.toggleAttribute("stuck", this.stuck);
    }
  };

  // js/hooks/_theme_selector.js
  var theme_selector_default = {
    mounted() {
      const form = document.querySelector("#backpex-theme-selector-form");
      const storedTheme = window.localStorage.getItem("backpexTheme");
      if (storedTheme != null) {
        const activeThemeRadio = form.querySelector(
          `input[name='theme-selector'][value='${storedTheme}']`
        );
        activeThemeRadio.checked = true;
      }
      window.addEventListener("backpex:theme-change", this.handleThemeChange.bind(this));
    },
    // Event listener that handles the theme changes and store
    // the selected theme in the session and also in localStorage
    handleThemeChange() {
      return __async(this, null, function* () {
        const form = document.querySelector("#backpex-theme-selector-form");
        const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
        const cookiePath = form.dataset.cookiePath;
        const selectedTheme = form.querySelector(
          'input[name="theme-selector"]:checked'
        );
        if (selectedTheme) {
          window.localStorage.setItem("backpexTheme", selectedTheme.value);
          document.documentElement.setAttribute(
            "data-theme",
            selectedTheme.value
          );
          yield fetch(cookiePath, {
            body: `select_theme=${selectedTheme.value}`,
            method: "POST",
            headers: {
              "Content-type": "application/x-www-form-urlencoded",
              "x-csrf-token": csrfToken
            }
          });
        }
      });
    },
    // Call this from your app.js as soon as possible to minimize flashes with the old theme in some situations.
    setStoredTheme() {
      const storedTheme = window.localStorage.getItem("backpexTheme");
      if (storedTheme != null) {
        document.documentElement.setAttribute("data-theme", storedTheme);
      }
    },
    destroyed() {
      window.removeEventListener("backpex:theme-change", this.handleThemeChange.bind(this));
    }
  };

  // js/hooks/_tooltip.js
  var tooltip_default = {
    mounted() {
      this.tooltip = null;
      this.controller = new AbortController();
      const signal = this.controller.signal;
      this.el.addEventListener("mouseenter", () => {
        const text = this.el.getAttribute("data-tooltip");
        if (!text) return;
        this.tooltip = document.createElement("div");
        this.tooltip.innerText = text;
        this.tooltip.className = `
        fixed z-50 -translate-x-1/2 px-2 py-1 bg-neutral rounded-field
        text-neutral-content text-sm shadow-sm whitespace-nowrap
        before:content-['']
        before:absolute before:w-0 before:h-0 before:left-1/2 before:-translate-x-1/2 before:top-full
        before:border-l-4 before:border-r-4 before:border-t-4 before:border-transparent before:border-t-neutral
      `;
        document.body.appendChild(this.tooltip);
        this.updateTooltipPosition();
      }, { signal });
      this.el.addEventListener("mouseleave", () => {
        if (this.tooltip) {
          this.tooltip.remove();
          this.tooltip = null;
        }
      }, { signal });
      window.addEventListener("scroll", () => {
        this.updateTooltipPosition();
      }, { signal });
    },
    destroyed() {
      this.controller.abort();
      if (this.tooltip) {
        this.tooltip.remove();
      }
    },
    updateTooltipPosition() {
      if (!this.tooltip) return;
      const rect = this.el.getBoundingClientRect();
      this.tooltip.style.left = `${rect.left + rect.width / 2}px`;
      this.tooltip.style.top = `${rect.top - this.tooltip.offsetHeight - 6}px`;
    }
  };
  return __toCommonJS(backpex_exports);
})();
