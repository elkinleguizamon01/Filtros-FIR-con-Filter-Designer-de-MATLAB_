# Laboratorio 2: Filtro FIR sobre FPGA con perturbación coherente

**Universidad Pedagógica y Tecnológica de Colombia (UPTC)**
Electrónica Digital II · Docente: Andrés David Suárez Gómez · Semestre 2026-II
**FPGA:** Altera DE1 (Cyclone II EP2C20F484C7) · **Semilla:** 64

## Descripción

Filtro FIR pasabajos en VHDL, sobre la DE1, que elimina una **perturbación cuadrada coherente** inyectada en la señal de un sensor de temperatura (LM35). La señal se digitaliza con un ADC0808, se filtra en la FPGA, se reconstruye con un DAC R-2R y se muestra en los displays de 7 segmentos.

### Idea clave: no hace falta filtro antialias analógico

La FPGA genera el instante de muestreo **y** la perturbación a partir de **un único contador**. Por construcción, la relación `Fs / f_n` es un **entero par exacto**, no un valor ajustado. Los armónicos de la onda cuadrada se pliegan sobre múltiplos impares de `f_n`, justo donde el filtro los atenúa.

Si la perturbación viniera de un oscilador externo (555, generador de funciones), la relación no sería exacta, los armónicos caerían sobre la banda útil y la medida se arruinaría.

## Parámetros del grupo (semilla 64)

| Parámetro | Símbolo | Valor |
|---|---|---|
| Frecuencia de muestreo | Fs | 320 Hz |
| Divisor | `DIV_FS` | 156 250 |
| Frecuencia de perturbación | f_n | 80 Hz (con `SW[1:0]=00`) |
| Relación Fs/f_n | r | 4 |
| Frecuencia de paso | Fpass | 30 Hz |
| Frecuencia de rechazo | Fstop | 80 Hz |
| Frecuencia de corte | Fc | 55 Hz |
| N.º de coeficientes | N | 35 |
| Ventana | | Blackman |
| Factor de escala | | 32 768 (2¹⁵) |
| Frecuencia de latido | f_latido | 160 Hz |
| Retardo de grupo | | 17 muestras |
| Retardo observable | | 18 muestras = 56.25 ms |

**Cómo se calcularon**

```
S = 64
S mod 4 = 0   →  Fs = {320, 400, 500, 800}[0] = 320 Hz
DIV_FS = 50e6 / 320 = 156250
S mod 5 = 4   →  Fpass = {10, 15, 20, 25, 30}[4] = 30 Hz
Fstop = Fs/4 = 80 Hz
Fc = (Fpass + Fstop) / 2 = 55 Hz
f_n = Fs/4 = 80 Hz      f_latido = Fs/2 = 160 Hz
```

## Arquitectura del sistema

```
LM35 → LM358 → Red de suma → ADC0808 → FPGA DE1 → DAC R-2R
sensor  ganancia 10×  Nodo N   8 bits    FIR 35 taps   8 bits
                        ▲
                        └── pert (GPIO_0[0], pin A13) generada por la misma FPGA
```

**Puntos de medida:** CH1 = Nodo N (sensor + perturbación) · CH2 = salida del DAC R-2R.

```
                 ┌──────────────┐  fsclk   ┌────────────────┐
 CLOCK_50 ─────▶ │ gen_muestreo │ ───────▶ │ adc0808_reader │◀── EOC, D[7:0]
                 └──────┬───────┘          └───────┬────────┘
                        │ pert, latido             │ sample_raw / sample_valid
                        ▼                          ▼
                    GPIO_0                   ┌───────────┐
                                             │ FIR_Filter│
                                             └─────┬─────┘
                                                   │ sample_fir
                          SW[2] ──▶ MUX (crudo / filtrado) ──▶ sample_dac
                                                   │
                       ┌───────────────────────────┼──────────────┐
                       ▼                           ▼              ▼
                  DAC R-2R (GPIO_0)         escalado a °C      LEDR
                                                   │
                                     bin_a_bcd ──▶ hex7seg ──▶ HEX0..HEX3
```

## Estructura del repositorio

```
Lab02_FIR_S64/
├── README.md
├── Lab02_FIR_S64.qpf              # Proyecto Quartus II
├── Lab02_FIR_S64.qsf              # Asignaciones de pines
├── vhdl/
│   ├── gen_muestreo.vhd           # fsclk, latido y pert
│   ├── adc0808_reader.vhd         # Controlador del ADC0808
│   ├── FIR_Filter.vhd             # Filtro FIR serie (35 coef.)
│   ├── bin_a_bcd.vhd              # Binario → BCD
│   ├── hex7seg.vhd                # Decodificador 7 segmentos
│   └── top_lab2.vhd               # Nivel superior
├── matlab/
│   ├── exportar_coeficientes.m    # Genera coeficientes.txt
│   ├── modelo_referencia.m        # Genera in.txt y ref.txt
│   └── coeficientes.txt           # Coeficientes en hex
├── sim/
│   ├── tb_FIR_Filter.vhd          # Testbench del filtro
│   ├── in.txt                     # 600 muestras de entrada
│   └── ref.txt                    # 600 muestras de salida esperada
└── docs/
    ├── Respuesta_FIR.png          # Respuesta del filtro en MATLAB
    ├── Esquematico.pdf            # Diagrama del circuito
    └── Capturas_Osciloscopio/     # Capturas de las 4 posiciones
```

## Módulos VHDL

### `gen_muestreo`: generador de muestreo coherente

Genera tres señales a partir de un único contador de 156 250 cuentas.

| Señal | Frecuencia | Uso |
|---|---|---|
| `fsclk` | 320 Hz | Dispara la conversión del ADC |
| `latido` | 160 Hz | Permite medir Fs con el osciloscopio |
| `pert` | 80 / 40 / 20 / 10 Hz | Perturbación cuadrada, según `SW[1:0]` |

La perturbación conmuta **medio período de muestreo antes** del pulso `fsclk`. Así las muestras caen en el centro de cada semiciclo, lo que maximiza el rechazo.

### `adc0808_reader`: controlador del ADC0808

```
S_REPOSO → S_ALE → S_START → S_ESPERA_BAJA → S_ESPERA_SUBE → S_LEE
```

- Reloj del ADC de 100 kHz (`CLK_DIV = 250`; rango válido del ADC: 10 kHz a 1.28 MHz).
- EOC sincronizado con 2 flip-flops (anti-metaestabilidad).
- Genera `valid_o` cuando hay un dato nuevo.
- Canal fijo: `addr_o = "000"` (los pines A, B y C del ADC van a GND).

### `FIR_Filter`: filtro FIR serie

Un único multiplicador, procesando las 35 muestras en 35 ciclos de reloj tras cada `fsclk`.

```
y[n] = (Σ c_k · x[n-1-k]) / 32768
```

- 35 coeficientes simétricos (fase lineal) en formato Q1.15.
- Suma de coeficientes = 32 768 exactos (ganancia unitaria en DC).
- Salida: bits `[30:15]` del acumulador de 32 bits (división por desplazamiento).
- Retardo de grupo de 17 muestras (18 en la implementación) = 56.25 ms.
- Si cambias `FILTER_TAPS`, hay que regenerar la tabla de coeficientes.

### `bin_a_bcd` y `hex7seg`

`bin_a_bcd` usa *double dabble* para convertir 12 bits a 3 dígitos BCD (máx. 999). `hex7seg` decodifica un dígito a 7 segmentos, activo en bajo.

### `top_lab2`: nivel superior

Instancia todos los módulos y conecta los pines.

| Elemento | Función |
|---|---|
| `KEY[0]` | Reset (`rst = not KEY(0)`) |
| `SW[1:0]` | Frecuencia de `pert` (80 / 40 / 20 / 10 Hz) |
| `SW[2]` | `0` = muestra cruda al DAC · `1` = muestra filtrada |
| `SW[3]` | `0` = displays en décimas de °C · `1` = código crudo del ADC |
| `HEX2..HEX0` | Valor en BCD (centenas, decenas, unidades) |
| `HEX3` | Letra "C" |
| `LEDR[0]` | Cambia de estado con cada muestra válida |
| `LEDR[9]` | Muestra en un extremo del rango (saturación) |

El display no muestra punto decimal: `245` equivale a 24.5 °C.

## Diseño del filtro en MATLAB

**Filter Designer**

| Campo | Valor |
|---|---|
| Response Type | Lowpass |
| Design Method | FIR → Window |
| Window | Blackman |
| Filter Order | Specify order: 34 |
| Units / Fs / Fc | Hz / 320 / 55 |

**Respuesta esperada**

| Frecuencia | Atenuación |
|---|---|
| 0 – 30 Hz (banda de paso) | 0 dB |
| 55 Hz (Fc) | −6 dB |
| 80 Hz (Fstop) | −70.5 dB (cumple 60 dB) |
| 160 Hz | −90 dB |

**Salida de `exportar_coeficientes.m`**

```
Coeficientes: 35
Suma: 32768 (debe ser 32768)
Mín/Máx: -1920 / 11262
Suma |c|: 47820
Margen acum: 21.9 veces
```

**Salida de `modelo_referencia.m`**

```
Vectores generados: 600 muestras
Rizado a la entrada: 390 códigos
Rizado a la salida : 2 códigos
Rechazo efectivo: 20·log10(390/2) = 45.8 dB
```

**Flujo de trabajo**

```matlab
filterDesigner            % configurar según la tabla y exportar Num al workspace
exportar_coeficientes     % convierte a enteros (suma = 32768)
modelo_referencia         % genera in.txt y ref.txt para el testbench
```

## Asignación de pines

### GPIO_0 (JP1)

| Señal | Pin FPGA | GPIO | Función |
|---|---|---|---|
| `GPIO_0_OUT[0]` | PIN_A13 | GPIO_0[0] | pert |
| `GPIO_0_OUT[1]` | PIN_B13 | GPIO_0[1] | latido |
| `GPIO_0_OUT[2]` | PIN_A14 | GPIO_0[2] | adc_clk |
| `GPIO_0_OUT[3]` | PIN_B14 | GPIO_0[3] | ale |
| `GPIO_0_OUT[4]` | PIN_A15 | GPIO_0[4] | start |
| `GPIO_0_OUT[5]` | PIN_B15 | GPIO_0[5] | oe |
| `GPIO_0_OUT[7]` | PIN_C21 | GPIO_0[16] | DAC bit 0 |
| `GPIO_0_OUT[8]` | PIN_C22 | GPIO_0[17] | DAC bit 1 |
| `GPIO_0_OUT[9]` | PIN_D21 | GPIO_0[18] | DAC bit 2 |
| `GPIO_0_OUT[10]` | PIN_D22 | GPIO_0[19] | DAC bit 3 |
| `GPIO_0_OUT[11]` | PIN_E21 | GPIO_0[20] | DAC bit 4 |
| `GPIO_0_OUT[12]` | PIN_E22 | GPIO_0[21] | DAC bit 5 |
| `GPIO_0_OUT[13]` | PIN_F21 | GPIO_0[22] | DAC bit 6 |
| `GPIO_0_OUT[14]` | PIN_F22 | GPIO_0[23] | DAC bit 7 |
| `GPIO_0_IN[0]` | PIN_B16 | GPIO_0[7] | eoc |
| `GPIO_0_IN[1..7]` | A17, B17, A18, B18, A19, B19, A20 | GPIO_0[8..14] | data[0..6] |

`GPIO_0_OUT[6]` queda sin uso (siempre `'0'`).

### GPIO_1 (JP2)

| Señal | Pin FPGA | GPIO | Función |
|---|---|---|---|
| `GPIO_1_IN[0]` | PIN_H14 | GPIO_1[2] | data[7] |

### Otros periféricos

| Señal | Pin | Función |
|---|---|---|
| `CLOCK_50` | PIN_L1 | Reloj de 50 MHz |
| `KEY[0]` | PIN_R22 | Reset |
| `SW[1:0]` | L22, L21 | Selector r |
| `SW[2]` | M22 | Bypass del filtro |
| `SW[3]` | V12 | Selector de display |
| `HEX0–HEX3` | J2–E2, E1–D1, G5–D3, F4–D4 | Displays de 7 segmentos |
| `LEDR[0]` | R20 | Indicador de muestreo |
| `LEDR[9]` | R17 | Indicador de saturación |

## Cómo compilar y programar

**Requisitos:** Quartus II 13.0 SP1 (Web Edition o superior) · MATLAB R2022a o superior · GHDL o ModelSim (opcional) · DE1.

**Compilar**

1. Abrir Quartus II → *File → Open Project* → `Lab02_FIR_S64.qpf`.
2. *Processing → Start Compilation* (Ctrl+L).
3. Verificar 0 errores en el *Compilation Report*.

**Programar**

1. Conectar el USB-Blaster y poner el switch RUN/PROG en **RUN**.
2. Encender la DE1.
3. *Tools → Programmer* → *Hardware Setup* → USB-Blaster.
4. *Add File* → `output_files/Lab02_FIR_S64.sof`.
5. Marcar *Program/Configure* y pulsar *Start*.

## Verificación experimental

1. **Latido:** en GPIO_0[1] (B13) debe verse una cuadrada de 160 Hz, 0–3.3 V.
2. **Perturbación:** en GPIO_0[0] (A13), con `SW[1:0]` = 00 / 01 / 10 / 11 → 80 / 40 / 20 / 10 Hz (r = 4 / 8 / 16 / 32).
3. **Reloj del ADC:** en GPIO_0[2] (A14) debe verse una cuadrada de 100 kHz.
4. **Comparar canales:**

   | `SW[2]` | `SW[1:0]` | f_n | CH2 esperado |
   |---|---|---|---|
   | 0 | cualquiera | — | CH1 y CH2 coinciden |
   | 1 | 00 | 80 Hz | Línea plana (residual ~3 mV) |
   | 1 | 01 | 40 Hz | Senoidal limpia |
   | 1 | 10 | 20 Hz | Senoidal de mayor amplitud |
   | 1 | 11 | 10 Hz | Cuadrada redondeada |

5. **Retardo:** con `SW[1:0]` = 01, unos 56.25 ms entre el flanco de CH1 y el pico de CH2.
6. **Temperatura:** al calentar el LM35 con el dedo, el valor en los displays debe subir y concordar con un termómetro dentro de ±2 °C.

## Resultados

**Tabla de registro de pruebas**

| # | Magnitud | Calculado | Medido |
|---|---|---|---|
| 1 | Latido / Fs | 160 Hz / 320 Hz | |
| 2 | Amplitud de perturbación en nodo N | 300 mVpp | |
| 3 | Voltaje en nodo N a temperatura ambiente | ~2.27 V | |
| 4 | Coincidencia de canales con `SW[2]=0` | — | |
| 5 | Perturbación CH1, `SW=00` | 300 mVpp | |
| 6 | Perturbación CH2, `SW=00` | ~3 mV | |
| 7 | Amplitud CH1/CH2, `SW=01` | — | |
| 8 | Amplitud CH1/CH2, `SW=10` | — | |
| 9 | Amplitud CH1/CH2, `SW=11` | — | |
| 10 | Retardo, `SW=01` | 56.25 ms | |
| 11 | Temperatura vs termómetro | ±2 °C | |

**Verificación del filtro**

| Parámetro | Valor |
|---|---|
| Suma de coeficientes | 32 768 exactos |
| Simulación FIR vs MATLAB | 0 LSB de diferencia |
| Atenuación teórica en 80 Hz | −70.5 dB |
| Rechazo del modelo de referencia | 45.8 dB |
| Rechazo medido experimentalmente | ~40 dB |

## Materiales

| Cant. | Componente |
|---|---|
| 1 | Altera DE1 (Cyclone II EP2C20F484C7) |
| 1 | LM35 (sensor de temperatura) |
| 1 | LM358 (amplificador operacional) |
| 1 | ADC0808 (conversor A/D de 8 bits) |
| 1 | Trimmer de 100 kΩ |
| 1 | R 10 kΩ (R1 del amplificador) |
| 1 | R 1 kΩ (R1 de inyección) |
| 1 | R 10 kΩ (R2 de inyección) |
| 1 | C 10 µF (acople de la perturbación) |
| 2 | C 100 nF (desacople) |
| 1 | C 100 µF (filtro de alimentación) |
| 9 | R 1.8 kΩ (divisores 5 V → 3.3 V) |
| 9 | R 3.3 kΩ (divisores 5 V → 3.3 V) |
| 8 | R 10 kΩ 1 % (DAC R-2R) |
| 8 | R 20 kΩ 1 % (DAC R-2R) |
| 1 | Protoboard |
| 1 | Osciloscopio de 2 canales |
| 1 | Multímetro |

## Problemas conocidos / pendientes

El ADC0808 es de **8 bits**, pero parte del `top_lab2` y de la documentación aún asume 10 bits:

- `GPIO_0_OUT(14 downto 7) <= sample_dac(9 downto 2)` atenúa la salida del DAC a 1/4. Debe ser `sample_dac(7 downto 0)`.
- `LEDR(9)` compara contra `"1111111111"` y nunca detecta saturación alta. Debe comparar 8 bits (`x"00"` / `x"FF"`).
- El escalado de temperatura `(código · 2907) >> 13` y el uso de `sample_dac(9 downto 0)` no corresponden a un ADC de 8 bits. Con el amplificador de ganancia 10 (LM35 × 10 = 100 mV/°C) y Vref = 5 V, cada LSB equivale a ≈ 0.195 °C, es decir ≈ 1.95 décimas de °C. Verifica la Vref real del montaje.
- La salida del FIR no se satura antes del DAC: valores negativos o mayores de 255 producen saltos de escala completa.
- En `S_LEE` el dato se captura antes de que el ADC0808 (hasta ~250 ns) lo tenga estable. Conviene esperar un tick adicional y sincronizar `data_i`.
- `S_ESPERA_BAJA` y `S_ESPERA_SUBE` no tienen timeout: si EOC no cambia, la FSM queda bloqueada hasta el reset.
- El diagrama de arquitectura original mencionaba un ADC de 10 bits; corresponde a 8 bits.

**Advertencias de hardware**

- El ADC0808 trabaja a 5 V y la FPGA a 3.3 V. Los divisores 1.8 kΩ / 3.3 kΩ (9 canales: EOC + 8 datos) protegen las entradas de la DE1; verifica también que la salida de 3.3 V de la FPGA alcance el VIH del ADC en ALE, START, OE y CLOCK.
- Los pines A, B y C del ADC deben ir a GND.

## Estado del proyecto

- [x] Diseño del filtro en MATLAB
- [x] Conversión de coeficientes a enteros (suma = 32 768)
- [x] Implementación VHDL de todos los módulos
- [x] Simulación con testbench (0 LSB de diferencia)
- [x] Compilación en Quartus II sin errores
- [x] Programación de la DE1
- [x] Verificación experimental con osciloscopio
- [ ] Corregir los puntos de "Problemas conocidos"
- [ ] Completar la columna "Medido" de la tabla de resultados

## Referencias

1. Guía de diseño de filtros FIR con Filter Designer de MATLAB, Aula Virtual.
2. DE1 User Manual v1.0.18, Terasic.
3. VHDLwhiz, serie "Digital Filters in FPGAs" (partes 1–4).
4. Video "Filtros FIR UPV": <https://www.youtube.com/watch?v=ENIFBriOrHI>
5. Video "Diseño de Filtros FIR e IIR en Matlab": <https://www.youtube.com/watch?v=qWKIQsCsuBQ>
6. Datasheet ADC0808, Texas Instruments.
7. Datasheet LM35, Texas Instruments.
8. Datasheet LM358, Texas Instruments.

## Autores

| Nombre | Código | Rol |
|---|---|---|
| [Nombre 1] | [Código 1] | Diseño VHDL, MATLAB |
| [Nombre 2] | [Código 2] | Montaje de hardware, mediciones |

*Última actualización: septiembre de 2026.*
