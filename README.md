# Presale ZUM - Prototipo de Preventa

Este repositorio contiene el **prototipo de presale** que usaremos para el despliegue de la **moneda de gobernanza (ZUM)** de la plataforma DeFi que venimos construyendo.

El objetivo de este estudio es validar una preventa por etapas con precios progresivos, control de cupos, compra con stablecoins y ETH, y buenas prácticas de seguridad antes de una salida a producción.

## Objetivo del contrato

El contrato `Presale` permite:

- Preventa por **3 etapas** con precio configurable.
- Distribución de supply de preventa en tramos acumulados (33.33% / 33.33% / 33.34%).
- Compra con **USDT / USDC**.
- Compra con **ETH** usando oráculo **Chainlink ETH/USD**.
- Sistema de **claim** al finalizar la preventa.
- Controles de seguridad operativa: `pause/unpause`, blacklist y retiros de emergencia con `onlyOwner`.

## Contexto del estudio

Parámetros base trabajados en esta iteración:

- `totalSupply` de ZUM: **1,000,000** tokens.
- Asignación para presale: **100,000** tokens (10%).
- Etapas de precio objetivo (USD):
  - Fase 1: `0.06`
  - Fase 2: `0.075`
  - Fase 3: `0.09`

Este esquema deja margen para etapa post-presale/listing sobre `0.10`.

## Testing

Se cubrieron dos niveles:

1. **Tests locales (unitarios)**
   - Lógica de fases por tiempo y por cupo.
   - Validación de compras con stables.
   - `pause/unpause`.
   - Validaciones de acceso `onlyOwner`.
   - `claim` post-presale.
   - validación de oráculo stale en entorno mock.

2. **Tests en fork de Arbitrum**
   - Lectura real de `ETH/USD` usando Chainlink.
   - Compra con ETH usando `vm.deal` (sin usar fondos reales).
   - Bloqueo de compra ETH cuando el contrato está pausado.

## Feed utilizado en Arbitrum

- Chainlink ETH/USD (Arbitrum One):
  - `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612`

## Comandos útiles

### Build

```bash
forge build
```

### Tests locales

```bash
forge test --match-path test/Presale.t.sol -vv
```

### Tests fork (si hay RPC configurada)

```bash
ARB_RPC_URL='wss://arbitrum-one-rpc.publicnode.com' forge test --match-contract PresaleForkTest -vv
```

> Nota: los tests de fork están preparados para no romper CI cuando `ARB_RPC_URL` no está definida.

## Próximos pasos

- Extender cobertura de edge-cases económicos (slippage/rounding en bordes de fase).
- Incorporar despliegue parametrizado por red (scripts Foundry).
- Preparar checklist de preproducción (roles, timelocks, monitoreo).

## Autoría

Estudio práctico de arquitectura y seguridad para el módulo de preventa de ZUM dentro del stack DeFi en desarrollo.
