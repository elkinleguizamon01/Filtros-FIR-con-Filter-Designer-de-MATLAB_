library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FIR_Filter is
    generic (
        FILTER_TAPS  : integer := 35;
        INPUT_WIDTH  : integer range 8 to 32 := 16;
        COEFF_WIDTH  : integer range 8 to 32 := 16;
        OUTPUT_WIDTH : integer range 8 to 32 := 16
    );
    port (
        clk    : in STD_LOGIC;
        fsclk  : in STD_LOGIC;
        data_i : in STD_LOGIC_VECTOR(INPUT_WIDTH-1 downto 0);
        data_o : out STD_LOGIC_VECTOR(OUTPUT_WIDTH-1 downto 0)
    );
end FIR_Filter;

architecture Behavioral of FIR_Filter is

    type input_registers is array(0 to FILTER_TAPS-1) of signed(INPUT_WIDTH-1 downto 0);
    signal delay_line_s : input_registers := (others => (others => '0'));

    -- ⚠ ESTA LÍNEA FALTABA
    type coefficients is array (0 to FILTER_TAPS-1) of signed(COEFF_WIDTH-1 downto 0);

    signal coeff_s : coefficients := (
        x"0000", x"FFFE", x"FFFC", x"000D", x"002E", x"0020", 
        x"FFA6", x"FF24", x"FF9D", x"0165", x"02B9", x"00CA", 
        x"FB98", x"F880", x"FED4", x"1003", x"236E", x"2BFE", 
        x"236E", x"1003", x"FED4", x"F880", x"FB98", x"00CA", 
        x"02B9", x"0165", x"FF9D", x"FF24", x"FFA6", x"0020", 
        x"002E", x"000D", x"FFFC", x"FFFE", x"0000");

    signal fs_ff1, fs_ff2, fs_ff3 : std_logic := '0';
    type state_machine is (idle_st, active_st);
    signal state : state_machine := idle_st;
    signal counter     : integer range 0 to FILTER_TAPS-1 := FILTER_TAPS-1;
    signal output      : signed(INPUT_WIDTH+COEFF_WIDTH-1 downto 0) := (others => '0');
    signal accumulator : signed(INPUT_WIDTH+COEFF_WIDTH-1 downto 0) := (others => '0');

begin
    data_o <= std_logic_vector(
        output(INPUT_WIDTH+COEFF_WIDTH-2 downto INPUT_WIDTH+COEFF_WIDTH-OUTPUT_WIDTH-1));

    process(clk)
        variable sum_v : signed(INPUT_WIDTH+COEFF_WIDTH-1 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            fs_ff1 <= fsclk;
            fs_ff2 <= fs_ff1;
            fs_ff3 <= fs_ff2;

            case state is
                when idle_st =>
                    if fs_ff2 = '1' and fs_ff3 = '0' then
                        state <= active_st;
                    end if;

                when active_st =>
                    if counter > 0 then
                        counter <= counter - 1;
                    else
                        counter <= FILTER_TAPS-1;
                        state   <= idle_st;
                    end if;

                    if counter > 0 then
                        delay_line_s(counter) <= delay_line_s(counter-1);
                    else
                        delay_line_s(counter) <= signed(data_i);
                    end if;

                    if counter > 0 then
                        sum_v       := delay_line_s(counter) * coeff_s(counter);
                        accumulator <= accumulator + sum_v;
                    else
                        accumulator <= (others => '0');
                        sum_v       := delay_line_s(counter) * coeff_s(counter);
                        output      <= accumulator + sum_v;
                    end if;
            end case;
        end if;
    end process;
end Behavioral;