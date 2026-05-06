const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';
const CYAN = '\x1b[36m';
const YELLOW = '\x1b[33m';

export function shouldUseColor(output: { isTTY?: boolean } = process.stdout): boolean {
  return Boolean(output.isTTY) && !Object.prototype.hasOwnProperty.call(process.env, 'NO_COLOR');
}

export function cyanBold(line: string, useColor = shouldUseColor()): string {
  return useColor ? `${BOLD}${CYAN}${line}${RESET}` : line;
}

export function yellowBold(line: string, useColor = shouldUseColor()): string {
  return useColor ? `${BOLD}${YELLOW}${line}${RESET}` : line;
}

export function yellow(line: string, useColor = shouldUseColor()): string {
  return useColor ? `${YELLOW}${line}${RESET}` : line;
}
