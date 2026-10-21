/* @ds-bundle: {"format":3,"namespace":"PicseeUiSystem_bb8eab","components":[{"name":"IconButton","sourcePath":"components/IconButton.jsx"},{"name":"Keycap","sourcePath":"components/Keycap.jsx"},{"name":"NavRow","sourcePath":"components/NavRow.jsx"}],"sourceHashes":{"components/IconButton.jsx":"6a9f9ddf4bb0","components/Keycap.jsx":"d82407106d9f","components/NavRow.jsx":"c6f1a3b9032c"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.PicseeUiSystem_bb8eab = window.PicseeUiSystem_bb8eab || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/IconButton.jsx
try { (() => {
function IconButton({
  label,
  children,
  onClick,
  pressed,
  disabled = false
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "ds-icon-button",
    "aria-label": label,
    title: label,
    "aria-pressed": pressed,
    disabled: disabled,
    onClick: onClick
  }, children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/Keycap.jsx
try { (() => {
function Keycap({
  children
}) {
  return /*#__PURE__*/React.createElement("kbd", {
    className: "ds-keycap"
  }, children);
}
Object.assign(__ds_scope, { Keycap });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/Keycap.jsx", error: String((e && e.message) || e) }); }

// components/NavRow.jsx
try { (() => {
function NavRow({
  label,
  icon,
  count,
  selected = false,
  onClick
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "ds-nav-row",
    "aria-current": selected ? 'page' : undefined,
    onClick: onClick
  }, icon, /*#__PURE__*/React.createElement("span", {
    className: "row-text"
  }, label), count !== undefined && /*#__PURE__*/React.createElement("span", {
    className: "row-count"
  }, count));
}
Object.assign(__ds_scope, { NavRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/NavRow.jsx", error: String((e && e.message) || e) }); }

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Keycap = __ds_scope.Keycap;

__ds_ns.NavRow = __ds_scope.NavRow;

})();
