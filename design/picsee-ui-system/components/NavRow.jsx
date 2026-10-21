import React from 'react';
export function NavRow({label, icon, count, selected=false, onClick}) { return <button type="button" className="ds-nav-row" aria-current={selected ? 'page' : undefined} onClick={onClick}>{icon}<span className="row-text">{label}</span>{count!==undefined&&<span className="row-count">{count}</span>}</button>; }
