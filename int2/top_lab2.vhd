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
    constant DISP_DIV  : integer := 25_000_000;  -- 2 Hz de refresco del display
    constant STRETCH   : integer := 2_500_000;   -- 50 ms para el LED de valid

    signal rst_m, rst_s : std_logic := '1';
    signal rst      : std_logic;
    signal sw_m, sw_s : std_logic_vector(2 downto 0) := (others => '0');

    signal fsclk    : std_logic;
    signal latido   : std_logic;
    signal pert     : std_logic;
    signal adc_data : std_logic_vector(15 downto 0);
    signal adc_valid: std_logic;
    signal fir_out  : std_logic_vector(15 downto 0);
    signal adc_bus  : std_logic_vector(7 downto 0);

    signal adc8     : unsigned(7 downto 0);
    signal fir8     : unsigned(7 downto 0);
    signal muestra  : unsigned(7 downto 0);
    signal dac_in   : std_logic_vector(7 downto 0);

    signal valid_cnt : integer range 0 to STRETCH := 0;
    signal disp_cnt  : integer range 0 to DISP_DIV-1 := 0;
    signal temp_dec  : std_logic_vector(11 downto 0) := (others => '0');
    signal bcd       : std_logic_vector(15 downto 0);
begin
    -- =========================================================
    -- Sincronizadores de reset y switches (2 FF)
    -- =========================================================
    process (CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            rst_m <= not KEY(0);  rst_s <= rst_m;
            sw_m  <= SW(2 downto 0);  sw_s <= sw_m;
        end if;
    end process;
    rst <= rst_s;

    -- =========================================================
    -- Bus de datos de 8 bits del ADC
    --   data[7]   <- GPIO_1_IN(0)
    --   data[6:0] <- GPIO_0_IN(7 downto 1)
    -- =========================================================
    adc_bus <= GPIO_1_IN(0) & GPIO_0_IN(7 downto 1);

    -- =========================================================
    -- Generador de muestreo y perturbacion
    -- =========================================================
    u_gen : entity work.gen_muestreo
        generic map (DIV_FS => 156250, DIV_LATIDO => 25000000)
        port map (clk=>CLOCK_50, rst=>rst, sel=>sw_s(1 downto 0),
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
    -- Saturacion de la salida del FIR a 0..255
    -- =========================================================
    adc8 <= unsigned(adc_data(7 downto 0));

    process (fir_out)
        variable f : signed(15 downto 0);
    begin
        f := signed(fir_out);
        if f < 0 then
            fir8 <= (others => '0');
        elsif f > 255 then
            fir8 <= (others => '1');
        else
            fir8 <= unsigned(f(7 downto 0));
        end if;
    end process;

    -- =========================================================
    -- Multiplexor SW[2]: crudo vs filtrado
    -- =========================================================
    muestra <= adc8 when sw_s(2) = '0' else fir8;

    -- =========================================================
    -- DAC R-2R (8 bits) en GPIO_0_OUT[14:7]
    -- =========================================================
    dac_in <= std_logic_vector(muestra);
    GPIO_0_OUT(14 downto 7) <= dac_in;

    -- =========================================================
    -- Salidas de control
    -- =========================================================
    GPIO_0_OUT(0) <= pert;
    GPIO_0_OUT(1) <= latido;
    GPIO_0_OUT(6) <= '0';   -- reservado

    -- =========================================================
    -- LEDs: valid estirado (50 ms), latido, resto apagados
    -- =========================================================
    process (CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if rst = '1' then
                valid_cnt <= 0;
            elsif adc_valid = '1' then
                valid_cnt <= STRETCH;
            elsif valid_cnt > 0 then
                valid_cnt <= valid_cnt - 1;
            end if;
        end if;
    end process;

    LEDR(0) <= '1' when valid_cnt > 0 else '0';
    LEDR(1) <= latido;
    LEDR(9 downto 2) <= (others => '0');

    -- =========================================================
    -- Escalado temperatura (decimas de grado), refresco a 2 Hz
    --   T = muestra * 4 * 2907 / 8192  (equivale a 10 bits: 255 -> 36.2 C)
    -- =========================================================
    process (CLOCK_50)
        variable temp_v : integer;
    begin
        if rising_edge(CLOCK_50) then
            if rst = '1' then
                temp_dec <= (others => '0');
                disp_cnt <= 0;
            elsif disp_cnt = DISP_DIV-1 then
                disp_cnt <= 0;
                temp_v   := (to_integer(muestra) * 11628) / 8192;
                temp_dec <= std_logic_vector(to_unsigned(temp_v, 12));
            else
                disp_cnt <= disp_cnt + 1;
            end if;
        end if;
    end process;

    -- =========================================================
    -- Conversion a BCD y visualizacion en HEX3..HEX0
    -- =========================================================
    u_bcd : entity work.bin_a_bcd
        port map (bin_in=>temp_dec, bcd_out=>bcd);

    u_h0 : entity work.hex7seg port map (hex_in=>bcd(3 downto 0),   seg_out=>HEX0);
    u_h1 : entity work.hex7seg port map (hex_in=>bcd(7 downto 4),   seg_out=>HEX1);
    u_h2 : entity work.hex7seg port map (hex_in=>bcd(11 downto 8),  seg_out=>HEX2);
    u_h3 : entity work.hex7seg port map (hex_in=>"1100",            seg_out=>HEX3);
end architecture;