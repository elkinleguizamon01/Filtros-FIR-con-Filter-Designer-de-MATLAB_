library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_lab2 is
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(3 downto 0);
        SW       : in  std_logic_vector(9 downto 0);
        -- GPIO_0 dividido (DE1 Tabla 4.7 - Expansion Header JP1)
        GPIO_0_IN  : in  std_logic_vector(7 downto 0);   -- eoc + data[0..6]
        GPIO_0_OUT : out std_logic_vector(14 downto 0);  -- pert, latido, ADC ctrl, DAC
        -- GPIO_1 para data[7] del ADC (DE1 Tabla 4.7 - Expansion Header JP2)
        GPIO_1_IN  : in  std_logic_vector(0 downto 0);   -- data[7]
        HEX0, HEX1, HEX2, HEX3 : out std_logic_vector(6 downto 0);
        LEDR     : out std_logic_vector(9 downto 0)
    );
end entity;

architecture rtl of top_lab2 is
    signal rst      : std_logic;
    signal fsclk    : std_logic;
    signal latido   : std_logic;
    signal pert     : std_logic;
    signal adc_data : std_logic_vector(15 downto 0);
    signal adc_valid: std_logic;
    signal fir_out  : std_logic_vector(15 downto 0);
    signal muestra  : std_logic_vector(15 downto 0);
    signal dac_in   : std_logic_vector(7 downto 0);
    signal adc_bus  : std_logic_vector(7 downto 0);

    signal temp_dec : std_logic_vector(11 downto 0);
    signal bcd      : std_logic_vector(15 downto 0);
begin
    rst <= not KEY(0);

    -- =========================================================
    -- Ensambla el bus de datos de 8 bits del ADC
    --   data[7]   <- GPIO_1_IN(0)
    --   data[6:0] <- GPIO_0_IN(7 downto 1)
    -- =========================================================
    adc_bus <= GPIO_1_IN(0) & GPIO_0_IN(7 downto 1);

    -- =========================================================
    -- Generador de muestreo y perturbación
    -- =========================================================
    u_gen : entity work.gen_muestreo
        generic map (DIV_FS => 156250)
        port map (clk=>CLOCK_50, rst=>rst, sel=>SW(1 downto 0),
                  fsclk=>fsclk, latido=>latido, pert=>pert);

    -- =========================================================
    -- Lector del ADC0808 (disparado por fsclk)
    -- =========================================================
    u_adc : entity work.adc0808_reader
        generic map (CLK_DIV=>250, CANAL=>0, DATA_WIDTH=>16)
        port map (
            clk       => CLOCK_50,
            rst       => rst,
            adc_clk_o => GPIO_0_OUT(2),
            ale_o     => GPIO_0_OUT(3),
            start_o   => GPIO_0_OUT(4),
            oe_o      => GPIO_0_OUT(5),
            eoc_i     => GPIO_0_IN(0),
            inicio_i  => fsclk,
            addr_o    => open,
            data_i    => adc_bus,
            data_o    => adc_data,
            valid_o   => adc_valid
        );

    -- =========================================================
    -- Filtro FIR
    -- =========================================================
    u_fir : entity work.FIR_Filter
        generic map (FILTER_TAPS=>35, INPUT_WIDTH=>16,
                     COEFF_WIDTH=>16, OUTPUT_WIDTH=>16)
        port map (clk=>CLOCK_50, fsclk=>adc_valid,
                  data_i=>adc_data, data_o=>fir_out);

    -- =========================================================
    -- Multiplexor SW[2]: crudo vs filtrado
    -- =========================================================
    muestra <= adc_data when SW(2)='0' else fir_out;

    -- =========================================================
    -- DAC R-2R (8 bits) en GPIO_0_OUT[14:7]
    -- =========================================================
    dac_in <= muestra(9 downto 2);
    GPIO_0_OUT(14 downto 7) <= dac_in;

    -- =========================================================
    -- Salidas de control
    -- =========================================================
    GPIO_0_OUT(0) <= pert;
    GPIO_0_OUT(1) <= latido;
    GPIO_0_OUT(6) <= '0';   -- reservado

    LEDR(0) <= adc_valid;

    -- =========================================================
    -- Escalado temperatura (décimas de grado)
    -- =========================================================
    process(CLOCK_50)
        variable temp_v : integer;
    begin
        if rising_edge(CLOCK_50) then
            if rst = '1' then
                temp_dec <= (others => '0');
            else
                temp_v := (to_integer(unsigned(muestra(9 downto 0))) * 2907) / 8192;
                temp_dec <= std_logic_vector(to_unsigned(temp_v, 12));
            end if;
        end if;
    end process;

    -- =========================================================
    -- Conversión a BCD y visualización en HEX3..HEX0
    -- =========================================================
    u_bcd : entity work.bin_a_bcd
        port map (bin_in=>temp_dec, bcd_out=>bcd);

    u_h0 : entity work.hex7seg port map (hex_in=>bcd(3 downto 0),   seg_out=>HEX0);
    u_h1 : entity work.hex7seg port map (hex_in=>bcd(7 downto 4),   seg_out=>HEX1);
    u_h2 : entity work.hex7seg port map (hex_in=>bcd(11 downto 8),  seg_out=>HEX2);
    u_h3 : entity work.hex7seg port map (hex_in=>"1100",            seg_out=>HEX3);
end architecture;