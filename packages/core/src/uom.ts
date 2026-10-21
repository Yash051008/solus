// Stock is integer pieces. Cartons (or any UoM) exist only as a conversion factor at input/display edges.
// The database re-does the conversion authoritatively (order_lines trigger); this is for UX only.

declare const piecesBrand: unique symbol;
export type Pieces = number & { readonly [piecesBrand]: true };

function assertPositiveInt(value: number, what: string): void {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${what} must be a positive integer, got ${value}`);
  }
}

export function toPieces(uomQty: number, piecesPerUom: number): Pieces {
  assertPositiveInt(uomQty, 'quantity');
  assertPositiveInt(piecesPerUom, 'pieces per unit');
  const pieces = uomQty * piecesPerUom;
  if (!Number.isSafeInteger(pieces)) throw new RangeError('quantity overflows');
  return pieces as Pieces;
}

/** 100 pieces at 24/carton -> { units: 4, remainder: 4 } */
export function splitPieces(pieces: number, piecesPerUom: number): { units: number; remainder: number } {
  if (!Number.isSafeInteger(pieces) || pieces < 0) throw new RangeError(`invalid piece count ${pieces}`);
  assertPositiveInt(piecesPerUom, 'pieces per unit');
  return { units: Math.floor(pieces / piecesPerUom), remainder: pieces % piecesPerUom };
}

/** "4 ctn + 4 pcs", "4 ctn", "4 pcs" */
export function formatPieces(pieces: number, piecesPerUom: number, uomLabel = 'ctn'): string {
  if (piecesPerUom === 1) return `${pieces} pcs`;
  const { units, remainder } = splitPieces(pieces, piecesPerUom);
  if (units === 0) return `${remainder} pcs`;
  return remainder === 0 ? `${units} ${uomLabel}` : `${units} ${uomLabel} + ${remainder} pcs`;
}
