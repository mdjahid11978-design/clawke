import { cyanBold, shouldUseColor, yellowBold } from './terminal-style.js';

export const IOS_CLIENT_URL = 'https://apps.apple.com/us/app/clawke/id6760453431';
export const RELEASES_URL = 'https://github.com/clawke/clawke/releases';

const BOX_WIDTH = 52;

function boxRule(left: string, right: string, useColor: boolean): string {
  return cyanBold(`${left}${'═'.repeat(BOX_WIDTH)}${right}`, useColor);
}

function boxLine(text: string, useColor: boolean): string {
  return cyanBold(`║${`  ${text}`.padEnd(BOX_WIDTH, ' ')}║`, useColor);
}

export function formatClientInstallBanner(useColor = shouldUseColor()): string[] {
  return [
    '',
    boxRule('╔', '╗', useColor),
    boxLine('Clawke Server is ready', useColor),
    boxLine('Install Clawke Client to connect', useColor),
    boxRule('╚', '╝', useColor),
    '',
    `   iOS:             ${yellowBold(IOS_CLIENT_URL, useColor)}`,
    `   Other platforms: ${yellowBold(RELEASES_URL, useColor)}`,
    '',
  ];
}

export function printClientInstallBanner(): void {
  for (const line of formatClientInstallBanner()) {
    console.log(line);
  }
}
