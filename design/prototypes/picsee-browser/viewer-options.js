(function () {
  const {
    useState,
    useEffect,
    useMemo,
    useRef,
    useLayoutEffect
  } = React;
  const {
    IconButton,
    Keycap,
    NavRow
  } = window.PicseeUiSystem_bb8eab;
  const Icon = window.PicseeIcon,
    Photo = window.PicseePhoto;
  const {
    PictureViewer
  } = window.PicseeViewerLayouts;
  function saved(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(key)) ?? fallback;
    } catch {
      return fallback;
    }
  }
  function App() {
    const [appearance, setAppearance] = useState(() => saved('picsee-v2-appearance', 'system'));
    const [systemDark, setSystemDark] = useState(() => matchMedia('(prefers-color-scheme: dark)').matches);
    const theme = appearance === 'system' ? systemDark ? 'dark' : 'light' : appearance;
    const [showNames, setShowNames] = useState(() => saved('picsee-v2-names', true)),
      [thumbFit, setThumbFit] = useState(() => saved('picsee-v2-thumb-fit', 'cover'));
    const [alwaysControls, setAlwaysControls] = useState(() => saved('picsee-v2-controls', false)),
      [libraryOpen, setLibraryOpen] = useState(true);
    const [learned, setLearned] = useState(() => saved('picsee-v2-learned', false));
    const [sidebarWidth, setSidebarWidth] = useState(() => saved('picsee-v2-sidebar-width', 196));
    const [photos, setPhotos] = useState(window.PICSEE_PHOTOS);
    const [folder, setFolder] = useState('japan');
    const [customFolders, setCustomFolders] = useState({});
    const [selected, setSelected] = useState('lakeside');
    const [viewer, setViewer] = useState(true);
    const variant = 'immersive';
    const [filmstrip, setFilmstrip] = useState(() => saved('picsee-v2-filmstrip', false));
    const [gridTools, setGridTools] = useState(null);
    const [sidebar, setSidebar] = useState(() => saved('picsee-v2-sidebar', false)),
      [inspector, setInspector] = useState(false);
    const [favorites, setFavorites] = useState(() => saved('picsee-prototype-favorites', ['alley', 'temple', 'shore']));
    const [recent, setRecent] = useState([]),
      [query, setQuery] = useState(''),
      [sortBy, setSortBy] = useState('name');
    const [cellSize, setCellSize] = useState(() => saved('picsee-v2-cell-size', 220)),
      [zoom, setZoom] = useState(null),
      [canvasSize, setCanvasSize] = useState({
        width: 0,
        height: 0,
        pixelRatio: 1
      }),
      [pan, setPan] = useState({
        x: 0,
        y: 0
      });
    const [help, setHelp] = useState(false),
      [toast, setToast] = useState(''),
      [dimensions, setDimensions] = useState({});
    const gridRef = useRef(null),
      viewportRef = useRef(null),
      scrollPosition = useRef(0),
      importRef = useRef(null),
      queryRef = useRef(null),
      helpCloseRef = useRef(null),
      drag = useRef(null),
      toastTimer = useRef(null),
      previousHelpFocus = useRef(null),
      objectUrls = useRef([]);
    const [dragging, setDragging] = useState(false);
    const folderLabels = {
      ...window.PICSEE_FOLDERS,
      ...customFolders,
      all: '所有照片',
      favorites: '个人收藏',
      recent: '最近查看'
    };
    const items = useMemo(() => {
      let list = photos.filter(p => folder === 'all' || folder === 'japan' && !p.local || folder === 'favorites' && favorites.includes(p.id) || folder === 'recent' && recent.includes(p.id) || p.group === folder);
      const q = query.trim().toLowerCase();
      if (q) list = list.filter(p => p.file.toLowerCase().includes(q));
      if (folder === 'recent') return list.sort((a, b) => recent.indexOf(a.id) - recent.indexOf(b.id));
      return [...list].sort((a, b) => sortBy === 'date' ? b.date.localeCompare(a.date) || a.file.localeCompare(b.file) : a.file.localeCompare(b.file, 'zh-CN', {
        numeric: true
      }));
    }, [photos, folder, favorites, recent, query, sortBy]);
    const current = items.find(p => p.id === selected) || items[0],
      position = items.findIndex(p => p.id === current?.id);
    useEffect(() => {
      const media = matchMedia('(prefers-color-scheme: dark)');
      const changed = e => setSystemDark(e.matches);
      media.addEventListener('change', changed);
      return () => media.removeEventListener('change', changed);
    }, []);
    useEffect(() => {
      document.documentElement.classList.remove('theme-light', 'theme-dark');
      document.documentElement.classList.add('theme-' + theme);
    }, [theme]);
    useEffect(() => {
      try {
        for (const [key, value] of Object.entries({
          'appearance': appearance,
          'names': showNames,
          'thumb-fit': thumbFit,
          'controls': alwaysControls,
          'learned': learned,
          'sidebar': sidebar,
          'sidebar-width': sidebarWidth,
          'cell-size': cellSize,
          'filmstrip': filmstrip
        })) localStorage.setItem('picsee-v2-' + key, JSON.stringify(value));
      } catch {}
    }, [appearance, showNames, thumbFit, alwaysControls, learned, sidebar, sidebarWidth, cellSize, filmstrip]);
    useEffect(() => {
      if (!viewer) return;
      const node = viewportRef.current;
      if (!node) return;
      const update = () => setCanvasSize({
        width: node.clientWidth,
        height: node.clientHeight,
        pixelRatio: devicePixelRatio || 1
      });
      update();
      const observer = new ResizeObserver(update);
      observer.observe(node);
      return () => observer.disconnect();
    }, [viewer]);
    useEffect(() => {
      try {
        localStorage.setItem('picsee-prototype-favorites', JSON.stringify(favorites));
      } catch {}
    }, [favorites]);
    useEffect(() => () => {
      objectUrls.current.forEach(URL.revokeObjectURL);
      clearTimeout(toastTimer.current);
    }, []);
    useEffect(() => {
      if (!items.length) {
        setViewer(false);
        setSelected(null);
      } else if (!items.some(p => p.id === selected)) setSelected(items[0].id);
    }, [items, selected]);
    useEffect(() => {
      setZoom(null);
      setPan({
        x: 0,
        y: 0
      });
      if (viewer && current && folder !== 'recent') setRecent(list => [current.id, ...list.filter(id => id !== current.id)]);
    }, [viewer, current?.id]);
    useEffect(() => {
      if (viewer) requestAnimationFrame(() => viewportRef.current?.focus({
        preventScroll: true
      }));
    }, [viewer]);
    useLayoutEffect(() => {
      if (!viewer && gridRef.current) {
        gridRef.current.scrollTop = scrollPosition.current;
      }
    }, [viewer]);
    useEffect(() => {
      if (viewer || !current) return;
      const node = document.querySelector(`[data-photo-id="${current.id}"]`);
      if (node && document.activeElement?.closest('.photo-grid')) node.scrollIntoView({
        block: 'nearest'
      });
    }, [current?.id, viewer]);
    useEffect(() => {
      if (!help) return;
      previousHelpFocus.current = document.activeElement;
      helpCloseRef.current?.focus();
      return () => previousHelpFocus.current?.focus();
    }, [help]);
    function notify(message) {
      setToast(message);
      clearTimeout(toastTimer.current);
      toastTimer.current = setTimeout(() => setToast(''), 2200);
    }
    function openViewer(id = current?.id) {
      if (!id) return;
      setLearned(true);
      scrollPosition.current = gridRef.current?.scrollTop || 0;
      setSelected(id);
      setViewer(true);
      setHelp(false);
      setGridTools(null);
    }
    function closeViewer() {
      setViewer(false);
      requestAnimationFrame(() => document.querySelector(`[data-photo-id="${selected}"]`)?.focus({
        preventScroll: true
      }));
    }
    function chooseFolder(next) {
      scrollPosition.current = 0;
      setFolder(next);
      setViewer(false);
      setQuery('');
      setHelp(false);
      requestAnimationFrame(() => {
        if (gridRef.current) gridRef.current.scrollTop = 0;
      });
    }
    function navigate(delta) {
      if (!items.length) return;
      const next = Math.max(0, Math.min(items.length - 1, position + delta));
      setSelected(items[next].id);
      if (!viewer) requestAnimationFrame(() => document.querySelector(`[data-photo-id="${items[next].id}"]`)?.focus());
    }
    function toggleFavorite(id = current?.id) {
      if (!id) return;
      const liked = favorites.includes(id);
      setFavorites(list => liked ? list.filter(x => x !== id) : [...list, id]);
      notify(liked ? '已从个人收藏移除' : '已加入个人收藏');
    }
    useEffect(() => {
      const onKey = e => {
        if (help) {
          if (e.key === 'Escape') {
            e.preventDefault();
            setHelp(false);
          }
          if (e.key === 'Tab') {
            e.preventDefault();
            helpCloseRef.current?.focus();
          }
          return;
        }
        if (e.defaultPrevented) return;
        if (gridTools && e.key === 'Escape') {
          e.preventDefault();
          setGridTools(null);
          return;
        }
        if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') {
          e.preventDefault();
          if (!viewer) {
            setGridTools('search');
            requestAnimationFrame(() => queryRef.current?.focus());
          }
          return;
        }
        if (e.metaKey || e.ctrlKey || e.altKey || e.target.closest('input,textarea,select,[contenteditable="true"]')) return;
        if (viewer && ['0', '1', '+', '=', '-'].includes(e.key)) {
          e.preventDefault();
          setPan({
            x: 0,
            y: 0
          });
          if (e.key === '0') setZoom(null);else if (e.key === '1') setZoom(1);else changeZoom(e.key === '-' ? -.1 : .1);
          return;
        }
        if (e.key === 'Escape' && viewer) {
          e.preventDefault();
          closeViewer();
          return;
        }
        if (e.key === ' ' && !e.repeat) {
          if (e.target.closest('button,a') && !e.target.closest('.photo-cell')) return;
          e.preventDefault();
          viewer ? closeViewer() : openViewer();
          return;
        }
        if (e.key === 'Enter' && !viewer && e.target.closest('.photo-cell')) {
          e.preventDefault();
          openViewer();
          return;
        }
        if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) {
          if (!viewer && !e.target.closest('.photo-grid')) return;
          e.preventDefault();
          let delta = e.key === 'ArrowLeft' ? -1 : e.key === 'ArrowRight' ? 1 : 0;
          if (!viewer && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
            const columns = getComputedStyle(document.querySelector('.photo-grid')).gridTemplateColumns.split(' ').length;
            delta = columns * (e.key === 'ArrowDown' ? 1 : -1);
          }
          if (delta) navigate(delta);
        }
      };
      document.addEventListener('keydown', onKey);
      return () => document.removeEventListener('keydown', onKey);
    }, [items, position, viewer, current, selected, help, gridTools, zoom, canvasSize, dimensions]);
    useEffect(() => {
      if (!gridTools) return;
      const outside = e => {
        if (!e.target.closest('.grid-tools-panel,.grid-toolbar-tools')) setGridTools(null);
      };
      document.addEventListener('pointerdown', outside);
      return () => document.removeEventListener('pointerdown', outside);
    }, [gridTools]);
    function importImages(e) {
      const files = Array.from(e.target.files || []).filter(f => f.type.startsWith('image/'));
      if (!files.length) {
        notify('未找到可浏览的图片');
        e.target.value = '';
        return;
      }
      const group = 'local-' + Date.now(),
        label = files[0].webkitRelativePath?.split('/')[0] || '导入的图片';
      const added = files.map((file, i) => {
        const src = URL.createObjectURL(file);
        objectUrls.current.push(src);
        return {
          id: group + '-' + i,
          title: file.name,
          file: file.name,
          src,
          group,
          date: new Date(file.lastModified).toISOString().slice(0, 10),
          bytes: file.size,
          local: true
        };
      });
      setCustomFolders(d => ({
        ...d,
        [group]: label
      }));
      setPhotos(p => [...p, ...added]);
      setFolder(group);
      setQuery('');
      setSelected(added[0].id);
      setViewer(false);
      notify('已添加 ' + files.length + ' 张图片');
      e.target.value = '';
    }
    function loaded(photo, e) {
      const img = e.currentTarget;
      setDimensions(d => d[photo.id]?.width === img.naturalWidth ? d : {
        ...d,
        [photo.id]: {
          width: img.naturalWidth,
          height: img.naturalHeight
        }
      });
    }
    function beginPan(e) {
      if (actualZoom <= fitScale || e.button !== 0) return;
      drag.current = {
        x: e.clientX,
        y: e.clientY,
        origin: pan
      };
      e.currentTarget.setPointerCapture(e.pointerId);
      setDragging(true);
    }
    function movePan(e) {
      if (!drag.current || !dim) return;
      const rect = viewportRef.current.getBoundingClientRect(),
        limitX = Math.max(0, (dim.width * actualZoom / pixelRatio - rect.width) / 2),
        limitY = Math.max(0, (dim.height * actualZoom / pixelRatio - rect.height) / 2);
      setPan({
        x: Math.max(-limitX, Math.min(limitX, drag.current.origin.x + e.clientX - drag.current.x)),
        y: Math.max(-limitY, Math.min(limitY, drag.current.origin.y + e.clientY - drag.current.y))
      });
    }
    function changeZoom(amount) {
      setZoom(Math.max(.05, Math.min(8, actualZoom + amount)));
      setPan({
        x: 0,
        y: 0
      });
    }
    function resizeSidebar(e) {
      e.preventDefault();
      const node = e.currentTarget;
      node.setPointerCapture(e.pointerId);
    }
    const sourceName = folderLabels[folder] || '文件夹',
      dim = dimensions[current?.id];
    const pixelRatio = canvasSize.pixelRatio || 1;
    const fitScale = dim && canvasSize.width ? Math.min(1, Math.max(1, canvasSize.width - 32) * pixelRatio / dim.width, Math.max(1, canvasSize.height - 32) * pixelRatio / dim.height) : 1;
    const actualZoom = zoom === null ? fitScale : zoom;
    const formatBytes = n => n ? (n / 1024 / 1024).toFixed(2) + ' MB' : '示例图片';
    const count = g => photos.filter(p => g === 'all' || g === 'japan' && !p.local || g === 'favorites' && favorites.includes(p.id) || g === 'recent' && recent.includes(p.id) || p.group === g).length;
    return /*#__PURE__*/React.createElement("div", {
      className: 'prototype-shell layout-exploration variant-' + variant + (viewer ? ' is-viewing' : ' is-grid'),
      style: {
        '--picsee-sidebar-width': sidebarWidth + 'px'
      },
      "data-screen-label": viewer ? '大图浏览' : '文件夹与缩略图网格'
    }, !viewer && /*#__PURE__*/React.createElement("header", {
      className: "titlebar"
    }, /*#__PURE__*/React.createElement("div", {
      className: "traffic",
      "aria-hidden": "true"
    }, /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null)), /*#__PURE__*/React.createElement("div", {
      className: "titlebar-middle",
      title: sourceName
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "folder",
      size: 14
    }), /*#__PURE__*/React.createElement("span", null, sourceName))), /*#__PURE__*/React.createElement("div", {
      className: 'workspace ' + (!sidebar ? 'sidebar-hidden' : '')
    }, sidebar && /*#__PURE__*/React.createElement("aside", {
      className: "sidebar",
      "aria-label": "\u6587\u4EF6\u5939\u4FA7\u680F"
    }, /*#__PURE__*/React.createElement("button", {
      className: "sidebar-heading library-toggle",
      "aria-expanded": libraryOpen,
      onClick: () => setLibraryOpen(!libraryOpen)
    }, "\u56FE\u5E93", /*#__PURE__*/React.createElement(Icon, {
      name: libraryOpen ? 'down' : 'right',
      size: 13
    })), libraryOpen && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(NavRow, {
      label: "\u6240\u6709\u7167\u7247",
      icon: /*#__PURE__*/React.createElement(Icon, {
        name: "image",
        size: 17
      }),
      count: count('all'),
      selected: folder === 'all',
      onClick: () => chooseFolder('all')
    }), /*#__PURE__*/React.createElement(NavRow, {
      label: "\u4E2A\u4EBA\u6536\u85CF",
      icon: /*#__PURE__*/React.createElement(Icon, {
        name: "heart",
        size: 17
      }),
      count: count('favorites'),
      selected: folder === 'favorites',
      onClick: () => chooseFolder('favorites')
    }), /*#__PURE__*/React.createElement(NavRow, {
      label: "\u6700\u8FD1\u67E5\u770B",
      icon: /*#__PURE__*/React.createElement(Icon, {
        name: "clock",
        size: 17
      }),
      count: count('recent'),
      selected: folder === 'recent',
      onClick: () => chooseFolder('recent')
    })), /*#__PURE__*/React.createElement("div", {
      className: "sidebar-heading folder-heading"
    }, /*#__PURE__*/React.createElement("span", null, "\u6587\u4EF6\u5939"), /*#__PURE__*/React.createElement("button", {
      className: "tiny-button",
      "aria-label": "\u6DFB\u52A0\u6587\u4EF6\u5939",
      title: "\u6DFB\u52A0\u672C\u5730\u56FE\u7247\u6587\u4EF6\u5939",
      onClick: () => importRef.current.click()
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "plus",
      size: 14
    }))), /*#__PURE__*/React.createElement(NavRow, {
      label: "\u65E5\u672C \xB7 \u5C71\u6D77\u4E4B\u95F4",
      icon: /*#__PURE__*/React.createElement(Icon, {
        name: "folderOpen",
        size: 17
      }),
      count: count('japan'),
      selected: folder === 'japan',
      onClick: () => chooseFolder('japan')
    }), /*#__PURE__*/React.createElement("div", {
      className: "folder-children"
    }, ['forest', 'coast', 'street'].map(g => /*#__PURE__*/React.createElement(NavRow, {
      key: g,
      label: folderLabels[g],
      icon: /*#__PURE__*/React.createElement(Icon, {
        name: "folder",
        size: 16
      }),
      count: count(g),
      selected: folder === g,
      onClick: () => chooseFolder(g)
    }))), Object.keys(customFolders).map(g => /*#__PURE__*/React.createElement(NavRow, {
      key: g,
      label: customFolders[g],
      icon: /*#__PURE__*/React.createElement(Icon, {
        name: "folder",
        size: 17
      }),
      count: count(g),
      selected: folder === g,
      onClick: () => chooseFolder(g)
    })), /*#__PURE__*/React.createElement("button", {
      className: "add-folder",
      onClick: () => importRef.current.click()
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "plus",
      size: 15
    }), /*#__PURE__*/React.createElement("span", null, "\u6DFB\u52A0\u6587\u4EF6\u5939")), /*#__PURE__*/React.createElement("div", {
      className: "sidebar-resizer",
      role: "separator",
      tabIndex: "0",
      "aria-label": "\u8C03\u6574\u4FA7\u680F\u5BBD\u5EA6",
      "aria-orientation": "vertical",
      "aria-valuemin": "160",
      "aria-valuemax": "320",
      "aria-valuenow": sidebarWidth,
      onKeyDown: e => {
        if (['ArrowLeft', 'ArrowRight'].includes(e.key)) {
          e.preventDefault();
          setSidebarWidth(w => Math.max(160, Math.min(320, w + (e.key === 'ArrowRight' ? 10 : -10))));
        }
      },
      onPointerDown: resizeSidebar,
      onPointerMove: e => {
        if (e.currentTarget.hasPointerCapture(e.pointerId)) setSidebarWidth(Math.max(160, Math.min(Math.min(320, innerWidth - 200), e.clientX)));
      },
      onPointerUp: e => e.currentTarget.releasePointerCapture(e.pointerId)
    })), /*#__PURE__*/React.createElement("main", {
      className: "main-content"
    }, !viewer ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
      className: "browser-body"
    }, /*#__PURE__*/React.createElement("div", {
      className: "grid-scroll",
      ref: gridRef,
      onScroll: e => scrollPosition.current = e.currentTarget.scrollTop
    }, items.length ? /*#__PURE__*/React.createElement("div", {
      className: "photo-grid",
      role: "listbox",
      "aria-label": "\u56FE\u7247\u7F51\u683C",
      style: {
        '--thumb-min': cellSize + 'px'
      }
    }, items.map(photo => /*#__PURE__*/React.createElement("button", {
      type: "button",
      key: photo.id,
      role: "option",
      className: 'photo-cell ' + (current?.id === photo.id ? 'is-selected' : ''),
      "aria-selected": current?.id === photo.id,
      "aria-label": photo.file,
      title: photo.file,
      "data-photo-id": photo.id,
      tabIndex: current?.id === photo.id ? 0 : -1,
      onFocus: () => setSelected(photo.id),
      onClick: () => setSelected(photo.id),
      onDoubleClick: () => openViewer(photo.id)
    }, /*#__PURE__*/React.createElement("div", {
      className: 'thumbnail-wrap thumb-' + thumbFit
    }, /*#__PURE__*/React.createElement(Photo, {
      photo: photo,
      onLoad: e => loaded(photo, e)
    }), favorites.includes(photo.id) && /*#__PURE__*/React.createElement("span", {
      className: "favorite-mark"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "heart",
      size: 13
    })), /*#__PURE__*/React.createElement("span", {
      className: "file-type"
    }, photo.local ? photo.file.split('.').pop().toUpperCase() : 'JPG')), showNames && /*#__PURE__*/React.createElement("div", {
      className: "photo-name"
    }, photo.file)))) : /*#__PURE__*/React.createElement("div", {
      className: "empty-state"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: query ? 'search' : 'image',
      size: 32
    }), /*#__PURE__*/React.createElement("h2", null, query ? '没有匹配的图片' : folder === 'favorites' ? '还没有收藏的图片' : folder === 'recent' ? '还没有浏览记录' : '文件夹里还没有图片'), /*#__PURE__*/React.createElement("p", null, query ? '试试其他名称，或清除搜索。' : folder === 'favorites' ? '打开任意大图，点击收藏即可加入。' : folder === 'recent' ? '选中一张图片，按 Space 开始浏览。' : '添加本地文件夹，开始浏览你的图片。'), query && /*#__PURE__*/React.createElement("button", {
      className: "text-button",
      onClick: () => setQuery('')
    }, "\u6E05\u9664\u641C\u7D22"))), inspector && current && /*#__PURE__*/React.createElement(Inspector, {
      photo: current,
      dim: dim,
      favorite: favorites.includes(current.id),
      onFavorite: () => toggleFavorite(),
      onClose: () => setInspector(false),
      formatBytes: formatBytes
    }))) : current && /*#__PURE__*/React.createElement(PictureViewer, {
      variant: variant,
      current: current,
      items: items,
      position: position,
      navigate: navigate,
      sidebar: sidebar,
      setSidebar: setSidebar,
      inspector: inspector,
      setInspector: setInspector,
      filmstrip: filmstrip,
      setFilmstrip: setFilmstrip,
      zoom: zoom,
      actualZoom: actualZoom,
      imageDimensions: dim,
      pixelRatio: pixelRatio,
      alwaysControls: alwaysControls,
      setAlwaysControls: setAlwaysControls,
      appearance: appearance,
      setAppearance: setAppearance,
      changeZoom: changeZoom,
      resetZoom: () => {
        setZoom(null);
        setPan({
          x: 0,
          y: 0
        });
      },
      closeViewer: closeViewer,
      theme: theme,
      help: help,
      setHelp: setHelp,
      favorite: favorites.includes(current.id),
      toggleFavorite: () => toggleFavorite(),
      viewportRef: viewportRef,
      beginPan: beginPan,
      movePan: movePan,
      endPan: () => {
        drag.current = null;
        setDragging(false);
      },
      dragging: dragging,
      pan: pan,
      loaded: loaded,
      setSelected: setSelected,
      inspectorContent: inspector && /*#__PURE__*/React.createElement(Inspector, {
        photo: current,
        dim: dim,
        favorite: favorites.includes(current.id),
        onFavorite: () => toggleFavorite(),
        onClose: () => setInspector(false),
        formatBytes: formatBytes
      })
    }))), !viewer && /*#__PURE__*/React.createElement("footer", {
      className: "grid-bottom-bar",
      "aria-label": "\u7F51\u683C\u5E95\u680F"
    }, /*#__PURE__*/React.createElement("div", {
      className: "grid-bottom-left"
    }, /*#__PURE__*/React.createElement(IconButton, {
      label: sidebar ? '隐藏侧栏' : '显示侧栏',
      pressed: sidebar,
      onClick: () => setSidebar(!sidebar)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "sidebar"
    })), /*#__PURE__*/React.createElement("span", {
      className: "toolbar-divider"
    }), /*#__PURE__*/React.createElement("div", {
      className: "grid-file-status"
    }, /*#__PURE__*/React.createElement("span", null, current?.file || sourceName), /*#__PURE__*/React.createElement("span", {
      className: "grid-folder-count"
    }, items.length, " \u5F20\u56FE\u7247"))), !learned && /*#__PURE__*/React.createElement("div", {
      className: "keyboard-hint"
    }, /*#__PURE__*/React.createElement(Keycap, null, "Space"), /*#__PURE__*/React.createElement("span", null, "\u5FEB\u901F\u67E5\u770B")), query && /*#__PURE__*/React.createElement("button", {
      className: "active-search",
      onClick: () => setQuery(''),
      title: "\u6E05\u9664\u641C\u7D22\uFF0C\u663E\u793A\u5168\u90E8\u56FE\u7247"
    }, "\u641C\u7D22\uFF1A", query, /*#__PURE__*/React.createElement(Icon, {
      name: "close",
      size: 13
    })), /*#__PURE__*/React.createElement("div", {
      className: "grid-toolbar-tools"
    }, /*#__PURE__*/React.createElement(IconButton, {
      label: "\u641C\u7D22\u56FE\u7247",
      pressed: gridTools === 'search' || !!query,
      onClick: () => {
        setGridTools(gridTools === 'search' ? null : 'search');
        requestAnimationFrame(() => queryRef.current?.focus());
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "search",
      size: 17
    })), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u56FE\u7247\u6392\u5E8F",
      pressed: gridTools === 'sort',
      onClick: () => setGridTools(gridTools === 'sort' ? null : 'sort')
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "sort",
      size: 17
    })), /*#__PURE__*/React.createElement(IconButton, {
      label: inspector ? '隐藏图片信息' : '显示图片信息',
      pressed: inspector,
      onClick: () => setInspector(!inspector)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "info",
      size: 17
    })), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u663E\u793A\u4E0E\u5916\u89C2",
      pressed: gridTools === 'display',
      onClick: () => setGridTools(gridTools === 'display' ? null : 'display')
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "grid",
      size: 17
    }))), gridTools && /*#__PURE__*/React.createElement("section", {
      className: "grid-tools-panel",
      "aria-label": gridTools === 'search' ? '搜索面板' : gridTools === 'sort' ? '排序面板' : '显示面板'
    }, /*#__PURE__*/React.createElement("header", null, /*#__PURE__*/React.createElement("strong", null, gridTools === 'search' ? '搜索当前文件夹' : gridTools === 'sort' ? '图片排序' : '显示与外观'), /*#__PURE__*/React.createElement(IconButton, {
      label: '关闭' + (gridTools === 'search' ? '搜索' : gridTools === 'sort' ? '排序' : '显示') + '面板',
      onClick: () => setGridTools(null)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "close",
      size: 15
    }))), gridTools === 'search' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("label", {
      className: "search"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "search",
      size: 15
    }), /*#__PURE__*/React.createElement("input", {
      ref: queryRef,
      type: "search",
      placeholder: "\u641C\u7D22\u6587\u4EF6\u540D",
      "aria-label": "\u641C\u7D22\u5F53\u524D\u6587\u4EF6\u5939",
      value: query,
      onChange: e => setQuery(e.target.value)
    })), /*#__PURE__*/React.createElement("div", {
      className: "grid-search-caption"
    }, /*#__PURE__*/React.createElement("span", null, items.length, " \u4E2A\u7ED3\u679C"), query && /*#__PURE__*/React.createElement("button", {
      className: "text-button",
      onClick: () => setQuery('')
    }, "\u6E05\u9664\u641C\u7D22"))) : gridTools === 'sort' ? /*#__PURE__*/React.createElement("label", {
      className: "grid-sort-label"
    }, "\u6392\u5E8F\u65B9\u5F0F", /*#__PURE__*/React.createElement("select", {
      "aria-label": "\u6392\u5E8F\u65B9\u5F0F",
      value: sortBy,
      onChange: e => setSortBy(e.target.value)
    }, /*#__PURE__*/React.createElement("option", {
      value: "name"
    }, "\u540D\u79F0\u6392\u5E8F"), /*#__PURE__*/React.createElement("option", {
      value: "date"
    }, "\u65E5\u671F\u4ECE\u65B0\u5230\u65E7"))) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("label", {
      className: "setting-row"
    }, "\u7F29\u7565\u56FE\u5927\u5C0F", /*#__PURE__*/React.createElement("input", {
      type: "range",
      min: "140",
      max: "280",
      step: "10",
      "aria-label": "\u7F29\u7565\u56FE\u5927\u5C0F",
      value: cellSize,
      onChange: e => setCellSize(+e.target.value)
    })), /*#__PURE__*/React.createElement("label", {
      className: "setting-row"
    }, "\u663E\u793A\u6587\u4EF6\u540D", /*#__PURE__*/React.createElement("input", {
      type: "checkbox",
      checked: showNames,
      onChange: e => setShowNames(e.target.checked)
    })), /*#__PURE__*/React.createElement("label", {
      className: "setting-row"
    }, "\u7F29\u7565\u56FE", /*#__PURE__*/React.createElement("select", {
      "aria-label": "\u7F29\u7565\u56FE\u663E\u793A\u65B9\u5F0F",
      value: thumbFit,
      onChange: e => setThumbFit(e.target.value)
    }, /*#__PURE__*/React.createElement("option", {
      value: "cover"
    }, "\u586B\u5145\u88C1\u526A"), /*#__PURE__*/React.createElement("option", {
      value: "contain"
    }, "\u5B8C\u6574\u663E\u793A"))), /*#__PURE__*/React.createElement("label", {
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
    }, "\u59CB\u7EC8\u663E\u793A\u5927\u56FE\u5DE5\u5177", /*#__PURE__*/React.createElement("input", {
      type: "checkbox",
      checked: alwaysControls,
      onChange: e => setAlwaysControls(e.target.checked)
    })), /*#__PURE__*/React.createElement("button", {
      className: "setting-help",
      onClick: () => {
        setGridTools(null);
        setHelp(true);
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "keyboard",
      size: 16
    }), "\u952E\u76D8\u5FEB\u6377\u952E")))), /*#__PURE__*/React.createElement("input", {
      ref: importRef,
      type: "file",
      webkitdirectory: "",
      multiple: true,
      accept: "image/*",
      hidden: true,
      onChange: importImages
    }), toast && /*#__PURE__*/React.createElement("div", {
      className: "toast",
      role: "status"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "check",
      size: 15
    }), toast), help && /*#__PURE__*/React.createElement("div", {
      className: "modal-scrim",
      onClick: () => setHelp(false)
    }, /*#__PURE__*/React.createElement("section", {
      className: "shortcut-modal",
      role: "dialog",
      "aria-modal": "true",
      "aria-labelledby": "help-title",
      onClick: e => e.stopPropagation()
    }, /*#__PURE__*/React.createElement("header", null, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "eyebrow"
    }, "PICSEE"), /*#__PURE__*/React.createElement("h2", {
      id: "help-title"
    }, "\u7528\u952E\u76D8\uFF0C\u987A\u624B\u4E00\u70B9")), /*#__PURE__*/React.createElement("button", {
      className: "tiny-button modal-close",
      ref: helpCloseRef,
      "aria-label": "\u5173\u95ED\u5FEB\u6377\u952E\u8BF4\u660E",
      onClick: () => setHelp(false)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "close"
    }))), /*#__PURE__*/React.createElement("p", null, "\u9009\u4E2D\u56FE\u7247\u540E\uFF0C\u53EF\u4EE5\u8FD9\u6837\u6D4F\u89C8\u3002"), [['Space', '打开 / 关闭大图'], ['←  →', '浏览上一张 / 下一张'], ['↑  ↓', '在网格中上下选择'], ['Esc', '返回网格，保留当前位置'], ['Enter', '打开选中的图片'], ['0 / 1', '适应窗口 / 1:1 原始尺寸'], ['+ / −', '放大 / 缩小图片']].map(([key, label]) => /*#__PURE__*/React.createElement("div", {
      className: "shortcut-row",
      key: key
    }, /*#__PURE__*/React.createElement("span", null, label), /*#__PURE__*/React.createElement(Keycap, null, key))), /*#__PURE__*/React.createElement("div", {
      className: "help-foot"
    }, "\u4E5F\u53EF\u4EE5\u53CC\u51FB\u7F29\u7565\u56FE\u6253\u5F00\u5927\u56FE\u3002"))));
  }
  function Inspector({
    photo,
    dim,
    favorite,
    onFavorite,
    onClose,
    formatBytes
  }) {
    const {
      IconButton
    } = window.PicseeUiSystem_bb8eab;
    return /*#__PURE__*/React.createElement("aside", {
      className: "inspector",
      "aria-label": "\u56FE\u7247\u4FE1\u606F"
    }, /*#__PURE__*/React.createElement("header", null, /*#__PURE__*/React.createElement("h2", null, "\u56FE\u7247\u4FE1\u606F"), /*#__PURE__*/React.createElement(IconButton, {
      label: "\u5173\u95ED\u56FE\u7247\u4FE1\u606F",
      onClick: onClose
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "close",
      size: 16
    }))), /*#__PURE__*/React.createElement(Photo, {
      photo: photo,
      className: "inspector-preview"
    }), /*#__PURE__*/React.createElement("h3", null, photo.file), /*#__PURE__*/React.createElement("p", {
      className: "inspector-title"
    }, photo.title), /*#__PURE__*/React.createElement("dl", null, /*#__PURE__*/React.createElement("dt", null, "\u5C3A\u5BF8"), /*#__PURE__*/React.createElement("dd", null, dim ? `${dim.width} × ${dim.height}` : '读取中'), /*#__PURE__*/React.createElement("dt", null, "\u7C7B\u578B"), /*#__PURE__*/React.createElement("dd", null, photo.local ? '本地图片' : 'JPEG'), /*#__PURE__*/React.createElement("dt", null, "\u65E5\u671F"), /*#__PURE__*/React.createElement("dd", null, photo.date), /*#__PURE__*/React.createElement("dt", null, "\u5927\u5C0F"), /*#__PURE__*/React.createElement("dd", null, formatBytes(photo.bytes))), /*#__PURE__*/React.createElement("button", {
      className: 'favorite-button ' + (favorite ? 'liked' : ''),
      onClick: onFavorite
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "heart",
      size: 16
    }), favorite ? '已加入个人收藏' : '加入个人收藏'), photo.demo && /*#__PURE__*/React.createElement("p", {
      className: "demo-note"
    }, "\u6F14\u793A\u7167\u7247 \xB7 \u6587\u4EF6\u540D\u4E0E\u65E5\u671F\u4E3A\u793A\u4F8B", /*#__PURE__*/React.createElement("br", null), "\u7167\u7247\u6765\u6E90\u89C1\u9879\u76EE\u8BF4\u660E"));
  }
  ReactDOM.createRoot(document.getElementById('root')).render(/*#__PURE__*/React.createElement(App, null));
})();