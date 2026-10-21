function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
(function () {
  const {
    useState,
    useEffect,
    useRef
  } = React;
  const {
    IconButton
  } = window.PicseeUiSystem_bb8eab;
  const Icon = window.PicseeIcon,
    Photo = window.PicseePhoto;
  function MoreIcon() {
    return /*#__PURE__*/React.createElement("svg", {
      width: "18",
      height: "18",
      viewBox: "0 0 24 24",
      fill: "currentColor",
      "aria-hidden": "true"
    }, /*#__PURE__*/React.createElement("circle", {
      cx: "5",
      cy: "12",
      r: "1.5"
    }), /*#__PURE__*/React.createElement("circle", {
      cx: "12",
      cy: "12",
      r: "1.5"
    }), /*#__PURE__*/React.createElement("circle", {
      cx: "19",
      cy: "12",
      r: "1.5"
    }));
  }
  function StripIcon() {
    return /*#__PURE__*/React.createElement("svg", {
      width: "18",
      height: "18",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      strokeWidth: "1.75",
      "aria-hidden": "true"
    }, /*#__PURE__*/React.createElement("rect", {
      x: "3",
      y: "5",
      width: "18",
      height: "14",
      rx: "2"
    }), /*#__PURE__*/React.createElement("path", {
      d: "M3 15h18M8 15v4m8-4v4"
    }));
  }
  function PictureViewer(p) {
    const {
      variant,
      current,
      items,
      position,
      navigate,
      sidebar,
      setSidebar,
      inspector,
      setInspector,
      filmstrip,
      setFilmstrip,
      zoom,
      changeZoom,
      resetZoom,
      closeViewer,
      theme,
      appearance,
      setAppearance,
      alwaysControls,
      setAlwaysControls,
      actualZoom,
      imageDimensions,
      pixelRatio,
      help,
      setHelp,
      favorite,
      toggleFavorite,
      viewportRef,
      beginPan,
      movePan,
      endPan,
      dragging,
      pan,
      loaded,
      setSelected,
      inspectorContent
    } = p;
    const [menuOpen, setMenuOpen] = useState(false),
      [awake, setAwake] = useState(true);
    const timeout = useRef(null),
      inControls = useRef(false),
      modality = useRef('pointer'),
      menuRef = useRef(null),
      menuButtonRef = useRef(null),
      layoutRef = useRef(null);
    const immersive = variant === 'immersive';
    const stopTimer = () => clearTimeout(timeout.current);
    function schedule() {
      stopTimer();
      if (!immersive || alwaysControls) return;
      timeout.current = setTimeout(() => {
        const focused = layoutRef.current?.contains(document.activeElement) && document.activeElement?.closest('[data-viewer-controls]');
        if (!inControls.current && !menuOpen && !filmstrip && !help && !inspector && !(focused && modality.current === 'keyboard')) setAwake(false);
      }, 2500);
    }
    function reveal() {
      setAwake(true);
      schedule();
    }
    useEffect(() => {
      setAwake(true);
      setMenuOpen(false);
      schedule();
      return stopTimer;
    }, [variant]);
    useEffect(() => {
      if (menuOpen || filmstrip || help || inspector || alwaysControls) {
        setAwake(true);
        stopTimer();
      } else {
        inControls.current = false;
        schedule();
      }
      return stopTimer;
    }, [menuOpen, filmstrip, help, inspector, alwaysControls, variant]);
    useEffect(() => {
      const key = e => {
        modality.current = 'keyboard';
        if (e.key === 'Tab') {
          if (immersive && !awake) {
            e.preventDefault();
            setAwake(true);
            requestAnimationFrame(() => layoutRef.current?.querySelector('.leading-pod button')?.focus());
          } else setAwake(true);
          stopTimer();
        }
      };
      const pointer = () => {
        modality.current = 'pointer';
      };
      document.addEventListener('keydown', key);
      document.addEventListener('pointerdown', pointer);
      return () => {
        document.removeEventListener('keydown', key);
        document.removeEventListener('pointerdown', pointer);
      };
    }, [immersive, awake]);
    useEffect(() => {
      if (!menuOpen) return;
      menuRef.current?.querySelector('button,input,select')?.focus();
      const outside = e => {
        if (!e.target.closest('.viewer-more-menu,.more-button-wrap')) setMenuOpen(false);
      };
      const keyboard = e => {
        if (e.key === 'Escape') {
          e.preventDefault();
          e.stopImmediatePropagation();
          setMenuOpen(false);
          menuButtonRef.current?.querySelector('button,input,select')?.focus();
        }
        if (e.key === 'Tab') {
          const buttons = [...menuRef.current.querySelectorAll('button,input,select')],
            idx = buttons.indexOf(document.activeElement);
          if (e.shiftKey && idx === 0 || !e.shiftKey && idx === buttons.length - 1) {
            e.preventDefault();
            setMenuOpen(false);
            menuButtonRef.current?.querySelector('button,input,select')?.focus();
          }
        }
      };
      document.addEventListener('pointerdown', outside);
      document.addEventListener('keydown', keyboard, true);
      return () => {
        document.removeEventListener('pointerdown', outside);
        document.removeEventListener('keydown', keyboard, true);
      };
    }, [menuOpen]);
    useEffect(() => {
      if (!layoutRef.current) return;
      const observer = new ResizeObserver(() => {
        const box = viewportRef.current?.getBoundingClientRect(),
          shell = layoutRef.current.closest('.workspace')?.getBoundingClientRect();
        if (box && shell) window.dispatchEvent(new CustomEvent('picsee-canvas-metrics', {
          detail: {
            height: Math.round(box.height),
            width: Math.round(box.width),
            percentage: Math.round(box.height / shell.height * 100)
          }
        }));
      });
      observer.observe(layoutRef.current);
      return () => observer.disconnect();
    }, [variant, sidebar, inspector]);
    function trackingEnter() {
      inControls.current = true;
      reveal();
      stopTimer();
    }
    function trackingLeave() {
      inControls.current = false;
      schedule();
    }
    const tracking = {
      onPointerEnter: trackingEnter,
      onPointerLeave: trackingLeave,
      onFocusCapture: () => {
        if (modality.current === 'keyboard') {
          setAwake(true);
          stopTimer();
        }
      },
      onBlurCapture: () => schedule()
    };
    const Zoom = () => /*#__PURE__*/React.createElement("div", _extends({
      className: "zoom-pod",
      "data-viewer-controls": "zoom"
    }, tracking, {
      onPointerDown: e => e.stopPropagation()
    }), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u7F29\u5C0F\u56FE\u7247",
      disabled: actualZoom <= .05,
      onClick: () => changeZoom(-.25)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "minus",
      size: 16
    })), /*#__PURE__*/React.createElement("select", {
      className: "zoom-label",
      "aria-label": "\u7F29\u653E\u6A21\u5F0F",
      value: zoom === null ? 'fit' : zoom === 1 ? 'actual' : 'custom',
      onChange: e => {
        if (e.target.value === 'fit') resetZoom();else if (e.target.value === 'actual') changeZoom(1 - actualZoom);
      }
    }, /*#__PURE__*/React.createElement("option", {
      value: "fit"
    }, "\u9002\u5E94\u7A97\u53E3"), /*#__PURE__*/React.createElement("option", {
      value: "actual"
    }, "1:1 \xB7 100%"), zoom !== null && zoom !== 1 && /*#__PURE__*/React.createElement("option", {
      value: "custom"
    }, Math.round(actualZoom * 100), "%")), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u653E\u5927\u56FE\u7247",
      disabled: actualZoom >= 8,
      onClick: () => changeZoom(.25)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "plus",
      size: 16
    })));
    const Navigation = () => /*#__PURE__*/React.createElement("div", _extends({
      className: "navigation-pod",
      "data-viewer-controls": "navigation"
    }, tracking), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u4E0A\u4E00\u5F20\u56FE\u7247",
      disabled: position === 0,
      onClick: () => navigate(-1)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "left",
      size: 17
    })), /*#__PURE__*/React.createElement("div", {
      className: "viewer-file-label"
    }, /*#__PURE__*/React.createElement("strong", null, current.file), /*#__PURE__*/React.createElement("span", null, position + 1, " / ", items.length)), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u4E0B\u4E00\u5F20\u56FE\u7247",
      disabled: position === items.length - 1,
      onClick: () => navigate(1)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "right",
      size: 17
    })));
    const Leading = () => /*#__PURE__*/React.createElement("div", _extends({
      className: "leading-pod",
      "data-viewer-controls": "leading"
    }, tracking), /*#__PURE__*/React.createElement(IconButton, {
      label: sidebar ? '隐藏侧栏' : '显示侧栏',
      pressed: sidebar,
      onClick: () => setSidebar(!sidebar)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "sidebar",
      size: 18
    })), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u8FD4\u56DE\u7F51\u683C",
      onClick: closeViewer
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "grid",
      size: 17
    })), /*#__PURE__*/React.createElement("span", {
      className: "more-button-wrap",
      ref: menuButtonRef
    }, /*#__PURE__*/React.createElement(IconButton, {
      label: "\u66F4\u591A\u6D4F\u89C8\u64CD\u4F5C",
      pressed: menuOpen,
      onClick: () => setMenuOpen(!menuOpen)
    }, /*#__PURE__*/React.createElement(MoreIcon, null))));
    return /*#__PURE__*/React.createElement("div", {
      ref: layoutRef,
      className: 'picture-viewer ' + (awake ? 'chrome-awake' : 'chrome-asleep') + (filmstrip ? ' strip-open' : ''),
      "data-testid": "large-viewer",
      "data-variant": variant
    }, /*#__PURE__*/React.createElement("div", {
      className: "picture-surface"
    }, /*#__PURE__*/React.createElement("div", {
      className: "picture-stage",
      ref: viewportRef,
      tabIndex: "0",
      "aria-label": "\u5927\u56FE\u753B\u5E03\uFF0C\u5DE6\u53F3\u7BAD\u5934\u7FFB\u56FE\uFF0CEsc \u8FD4\u56DE",
      onPointerDown: beginPan,
      onPointerMove: e => {
        movePan(e);
        if (immersive) {
          const box = e.currentTarget.getBoundingClientRect();
          if (e.clientY > box.bottom - 90 || e.clientY < box.top + 38) reveal();else if (awake && !inControls.current) schedule();
        }
      },
      onPointerUp: endPan,
      onPointerCancel: endPan,
      style: {
        cursor: zoom !== null ? dragging ? 'grabbing' : 'grab' : 'default'
      }
    }, /*#__PURE__*/React.createElement(Photo, {
      photo: current,
      key: current.id,
      className: "large-image",
      onLoad: e => loaded(current, e),
      style: {
        width: imageDimensions ? imageDimensions.width * actualZoom / pixelRatio : undefined,
        height: imageDimensions ? imageDimensions.height * actualZoom / pixelRatio : undefined,
        transform: `translate(${pan.x}px,${pan.y}px)`
      }
    }), /*#__PURE__*/React.createElement("div", {
      className: "native-window-hint",
      "aria-hidden": "true"
    }, /*#__PURE__*/React.createElement("div", {
      className: "traffic"
    }, /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null))), /*#__PURE__*/React.createElement("div", {
      className: "viewer-floating-controls",
      onPointerDown: e => e.stopPropagation(),
      inert: immersive && !awake ? '' : undefined
    }, Zoom(), Leading(), Navigation(), menuOpen && /*#__PURE__*/React.createElement("div", _extends({
      ref: menuRef,
      className: "viewer-more-menu",
      "data-viewer-controls": "menu",
      role: "group",
      "aria-label": "\u66F4\u591A\u6D4F\u89C8\u64CD\u4F5C\u83DC\u5355"
    }, tracking), /*#__PURE__*/React.createElement("div", {
      className: "menu-file-name"
    }, current.file, /*#__PURE__*/React.createElement("span", null, current.title)), /*#__PURE__*/React.createElement("button", {
      onClick: () => {
        toggleFavorite();
        setMenuOpen(false);
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "heart",
      size: 16
    }), favorite ? '取消收藏' : '收藏图片'), /*#__PURE__*/React.createElement("button", {
      onClick: () => {
        setFilmstrip(!filmstrip);
        setMenuOpen(false);
      }
    }, /*#__PURE__*/React.createElement(StripIcon, null), filmstrip ? '隐藏缩略图条' : '显示缩略图条'), /*#__PURE__*/React.createElement("button", {
      onClick: () => {
        setInspector(!inspector);
        setMenuOpen(false);
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "info",
      size: 16
    }), inspector ? '隐藏图片信息' : '显示图片信息'), /*#__PURE__*/React.createElement("div", {
      className: "menu-separator"
    }), /*#__PURE__*/React.createElement("label", {
      className: "setting-row"
    }, "\u5916\u89C2", /*#__PURE__*/React.createElement("select", {
      "aria-label": "\u5916\u89C2",
      value: appearance,
      onChange: e => setAppearance(e.target.value)
    }, /*#__PURE__*/React.createElement("option", {
      value: "system"
    }, "\u8DDF\u968F\u7CFB\u7EDF"), /*#__PURE__*/React.createElement("option", {
      value: "light"
    }, "\u6D45\u8272"), /*#__PURE__*/React.createElement("option", {
      value: "dark"
    }, "\u6DF1\u8272"))), /*#__PURE__*/React.createElement("label", {
      className: "setting-row"
    }, "\u59CB\u7EC8\u663E\u793A\u5DE5\u5177", /*#__PURE__*/React.createElement("input", {
      type: "checkbox",
      checked: alwaysControls,
      onChange: e => setAlwaysControls(e.target.checked)
    })), /*#__PURE__*/React.createElement("button", {
      onClick: () => {
        setHelp(true);
        setMenuOpen(false);
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "keyboard",
      size: 16
    }), "\u952E\u76D8\u5FEB\u6377\u952E"))), filmstrip && /*#__PURE__*/React.createElement("div", _extends({
      className: "picture-filmstrip",
      "data-viewer-controls": "filmstrip",
      "aria-label": "\u5927\u56FE\u6D4F\u89C8\u7F29\u7565\u56FE\u6761"
    }, tracking, {
      onPointerDown: e => e.stopPropagation()
    }), items.map(photo => /*#__PURE__*/React.createElement("button", {
      key: photo.id,
      "aria-label": '查看 ' + photo.file,
      "aria-current": photo.id === current.id ? 'true' : undefined,
      className: photo.id === current.id ? 'active' : '',
      onClick: () => setSelected(photo.id),
      ref: node => {
        if (node && photo.id === current.id) node.scrollIntoView({
          block: 'nearest',
          inline: 'nearest'
        });
      }
    }, /*#__PURE__*/React.createElement(Photo, {
      photo: photo
    }))))), inspectorContent));
  }
  window.PicseeViewerLayouts = {
    PictureViewer
  };
})();