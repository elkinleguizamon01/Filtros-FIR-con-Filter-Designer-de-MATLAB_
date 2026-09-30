library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_lab2 is
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(3 downto 0);
        SW       : in  std_logic_vector(9 downto 0);
        -- GPIO_0 dividido (DE1 Tabla 4.7)
        GPIO_0_IN  : in  std_logic_vector(7 downto 0);   -- eoc + data[0..6]
        GPIO_0_OUT : out std_logic_vector(14 downto 0);  -- pert, latido, ADC ctrl, DAC
        -- GPIO_1 para data[7]
        GPIO_1_IN  : in  std_logic_vector(0 downto 0);
        HEX0, HEX1, HEX2, HEX3 : out std_logic_vector(6 downto 0);
        LEDR     : out std_logic_vector(9 downto 0)
    );
end entity;

architecture rtl of top_lab2 is

    signal rst          : std_logic;
    signal fsclk        : std_logic;
    signal sample_valid : std_logic;
    signal sample_raw   : std_logic_vector(15 downto 0) := (others => '0');
    signal sample_fir   : std_logic_vector(15 downto 0) := (others => '0');
    signal sample_dac   : std_logic_vector(15 downto 0) := (others => '0');
    signal adc_bus      : std_logic_vector(7 downto 0);

    signal temp_decimas : unsigned(11 downto 0) := (others => '0');
    signal valor_disp   : std_logic_vector(11 downto 0) := (others => '0');
    signal bcd_centenas : std_logic_vector(3 downto 0);
    signal bcd_decenas  : std_logic_vector(3 downto 0);
    signal bcd_unidades : std_logic_vector(3 downto 0);

    signal led_mues_reg : std_logic := '0';
    signal latido       : std_logic;
    signal pert         : std_logic;

begin

    rst <= not KEY(0);

    -- Ensambla bus de datos del ADC (data[7] viene de GPIO_1)
    adc_bus <= GPIO_1_IN(0) & GPIO_0_IN(7 downto 1);

    -- 1. Generador de muestreo coherente
    u_gen_muestreo : entity work.gen_muestreo
        generic map (
            DIV_FS => 156250    -- ⚠ CAMBIO: 50 MHz / 320 Hz
        )
        port map (
            clk    => CLOCK_50,
            rst    => rst,
            sel    => SW(1 downto 0),
            fsclk  => fsclk,
            latido => latido,
            pert   => pert
        );

    -- 2. Lector del ADC0808
    u_adc_reader : entity work.adc0808_reader
        generic map (
            CLK_DIV    => 250,
            DATA_WIDTH => 16
        )
        port map (
            clk       => CLOCK_50,
            rst       => rst,
            inicio_i  => fsclk,
            adc_clk_o => GPIO_0_OUT(2),
            ale_o     => GPIO_0_OUT(3),
            start_o   => GPIO_0_OUT(4),
            oe_o      => GPIO_0_OUT(5),
            eoc_i     => GPIO_0_IN(0),
            addr_o    => open,
            data_i    => adc_bus,
            data_o    => sample_raw,
            valid_o   => sample_valid
        );

    -- 3. Filtro FIR serie
    u_fir_filter : entity work.FIR_Filter
        generic map (
            FILTER_TAPS  => 35,   -- ⚠ CAMBIO: semilla 64 = 35 coef
            INPUT_WIDTH  => 16,
            COEFF_WIDTH  => 16,
            OUTPUT_WIDTH => 16
        )
        port map (
            clk    => CLOCK_50,
            fsclk  => sample_valid,
            data_i => sample_raw,
            data_o => sample_fir
        );

    -- 4. Multiplexor SW[2]: crudo o filtrado
    sample_dac <= sample_fir when SW(2) = '1' else sample_raw;

    -- 5. DAC R-2R: tomar bits 9..2 del rango útil
    GPIO_0_OUT(14 downto 7) <= sample_dac(9 downto 2);

    -- 6. Salidas de control
    GPIO_0_OUT(0) <= pert;
    GPIO_0_OUT(1) <= latido;
    GPIO_0_OUT(6) <= '0';

    -- 7. Escalado a décimas: T_decimas = (código * 2907) >> 13
    process(CLOCK_50)
        variable prod : unsigned(21 downto 0);
    begin
        if rising_edge(CLOCK_50) then
            prod         := unsigned(sample_dac(9 downto 0)) * to_unsigned(2907, 12);
            temp_decimas <= resize(prod(21 downto 13), 12);
        end if;
    end process;

    -- 8. Selector de visualización con SW[3]
    valor_disp <= std_logic_vector(temp_decimas) when SW(3) = '0' else
                  std_logic_vector(resize(unsigned(sample_raw(9 downto 0)), 12));

    -- 9. BCD y displays
    u_bcd : entity work.bin_a_bcd
        port map (
            bin_i      => valor_disp,
            centenas_o => bcd_centenas,
            decenas_o  => bcd_decenas,
            unidades_o => bcd_unidades
        );

    u_disp0 : entity work.hex7seg
        port map (hex_i => bcd_unidades, seg_o => HEX0);

    u_disp1 : entity work.hex7seg
        port map (hex_i => bcd_decenas,  seg_o => HEX1);

    u_disp2 : entity work.hex7seg
        port map (hex_i => bcd_centenas, seg_o => HEX2);

    u_disp3 : entity work.hex7seg
        port map (hex_i => "1100",       seg_o => HEX3);  -- letra C

    -- 10. LEDs
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if sample_valid = '1' then
                led_mues_reg <= not led_mues_reg;
            end if;
        end if;
    end process;

    LEDR(0) <= led_mues_reg;
    LEDR(9) <= '1' when (sample_raw(9 downto 0) = "0000000000" or
                         sample_raw(9 downto 0) = "1111111111") else '0';
    LEDR(8 downto 1) <= (others => '0');

end architecture;