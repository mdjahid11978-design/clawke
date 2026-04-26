export class GatewayBoundaryFinalizer {
  private readonly boundaryFinalizedTexts = new Set<string>();

  recordBoundaryFinalized(text: string): void {
    const key = normalizeText(text);
    if (key) {
      this.boundaryFinalizedTexts.add(key);
    }
  }

  consumeDuplicateFinal(text: string): boolean {
    const key = normalizeText(text);
    if (!key || !this.boundaryFinalizedTexts.has(key)) {
      return false;
    }
    this.boundaryFinalizedTexts.delete(key);
    return true;
  }
}

function normalizeText(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}
