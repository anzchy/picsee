import React from 'react';
export function IconButton({label, children, onClick, pressed, disabled=false}) {
  return <button type="button" className="ds-icon-button" aria-label={label} title={label} aria-pressed={pressed} disabled={disabled} onClick={onClick}>{children}</button>;
}
