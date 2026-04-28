export interface GatewayStartConfig {
  start_shell?: unknown;
}

export function resolveGatewayStartShell(gateway: GatewayStartConfig): string | null {
  if (typeof gateway.start_shell !== 'string') return null;
  const startShell = gateway.start_shell.trim();
  return startShell.length > 0 ? startShell : null;
}
