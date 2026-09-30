library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc0808_reader is
    generic (
        CLK_DIV    : positive := 250;   -- f_ADC = 100 kHz (50 MHz / (2*250))
        CANAL      : integer range 0 to 7 := 0;
        DATA_WIDTH : positive := 16;
        TIMEOUT    : positive := 200    -- en ticks de 5 us (=1 ms)
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        adc_clk_o : out std_logic;
        ale_o     : out std_logic;
        start_o   : out std_logic;
        oe_o      : out std_logic;
        eoc_i     : in  std_logic;
        inicio_i  : in  std_logic;   -- conectar a fsclk
        addr_o    : out std_logic_vector(2 downto 0);
        data_i    : in  std_logic_vector(7 downto 0);
        data_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_o   : out std_logic
    );
end entity;

architecture rtl of adc0808_reader is
    type t_estado is (S_REPOSO, S_ALE, S_START, S_ESPERA_BAJA,
                      S_ESPERA_SUBE, S_OE, S_LEE);
    signal estado  : t_estado := S_REPOSO;
    signal clk_cnt : integer range 0 to CLK_DIV-1 := 0;
    signal adc_clk : std_logic := '0';
    signal tick    : std_logic := '0';
    signal cnt     : integer range 0 to 7 := 0;
    signal to_cnt  : integer range 0 to TIMEOUT := 0;
    signal eoc_1, eoc_2 : std_logic := '1';
begin
    addr_o    <= std_logic_vector(to_unsigned(CANAL, 3));
    adc_clk_o <= adc_clk;

    reloj : process (clk)
    begin
        if rising_edge(clk) then
            tick <= '0';
            if rst = '1' then
                clk_cnt <= 0; adc_clk <= '0';
            elsif clk_cnt = CLK_DIV-1 then
                clk_cnt <= 0;
                adc_clk <= not adc_clk;
                tick    <= '1';
            else
                clk_cnt <= clk_cnt + 1;
            end if;
        end if;
    end process;

    fsm : process (clk)
    begin
        if rising_edge(clk) then
            eoc_1 <= eoc_i;  eoc_2 <= eoc_1;
            valid_o <= '0';
            if rst = '1' then
                estado  <= S_REPOSO; cnt <= 0; to_cnt <= 0;
                ale_o   <= '0'; start_o <= '0'; oe_o <= '0';
                data_o  <= (others => '0');
            else
                case estado is
                    when S_REPOSO =>
                        ale_o <= '0'; start_o <= '0'; oe_o <= '0';
                        if inicio_i = '1' then
                            cnt <= 0; to_cnt <= 0; estado <= S_ALE;
                        end if;

                    when S_ALE =>
                        ale_o <= '1'; start_o <= '0'; oe_o <= '0';
                        if tick = '1' then
                            if cnt = 1 then
                                cnt <= 0; estado <= S_START;
                            else
                                cnt <= cnt + 1;
                            end if;
                        end if;

                    when S_START =>
                        ale_o <= '0'; start_o <= '1';
                        if tick = '1' then
                            if cnt = 1 then
                                start_o <= '0'; cnt <= 0; to_cnt <= 0;
                                estado <= S_ESPERA_BAJA;
                            else
                                cnt <= cnt + 1;
                            end if;
                        end if;

                    when S_ESPERA_BAJA =>
                        start_o <= '0';
                        if eoc_2 = '0' then
                            to_cnt <= 0; estado <= S_ESPERA_SUBE;
                        elsif tick = '1' then
                            if to_cnt = TIMEOUT then      -- EOC nunca bajo
                                to_cnt <= 0; estado <= S_REPOSO;
                            else
                                to_cnt <= to_cnt + 1;
                            end if;
                        end if;

                    when S_ESPERA_SUBE =>
                        if eoc_2 = '1' then
                            cnt <= 0; estado <= S_OE;
                        elsif tick = '1' then
                            if to_cnt = TIMEOUT then      -- EOC nunca subio
                                to_cnt <= 0; estado <= S_REPOSO;
                            else
                                to_cnt <= to_cnt + 1;
                            end if;
                        end if;

                    when S_OE =>                          -- OE en alto ~10 us
                        oe_o <= '1';
                        if tick = '1' then
                            if cnt = 1 then
                                cnt <= 0; estado <= S_LEE;
                            else
                                cnt <= cnt + 1;
                            end if;
                        end if;

                    when S_LEE =>                         -- OE aun '1' (registrado)
                        data_o  <= std_logic_vector(resize(unsigned(data_i), DATA_WIDTH));
                        valid_o <= '1';
                        oe_o    <= '0';
                        estado  <= S_REPOSO;
                end case;
            end if;
        end if;
    end process;
end architecture;