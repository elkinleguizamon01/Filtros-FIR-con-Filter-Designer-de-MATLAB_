library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gen_muestreo is
    generic (
        DIV_FS : positive := 156250
    );
    port (
        clk    : in std_logic;
        rst    : in std_logic;                      -- activo en alto
        sel    : in std_logic_vector(1 downto 0);   -- 00:r=4, 01:r=8, 10:r=16, 11:r=32
        fsclk  : out std_logic;
        latido : out std_logic;
        pert   : out std_logic
    );
end entity gen_muestreo;

architecture rtl of gen_muestreo is

    function semiciclo (s : std_logic_vector(1 downto 0)) return integer is
    begin
        case s is
            when "00"   => return 2;  -- r = 4 (f_n = 80z)
            when "01"   => return 4;  -- r = 8 (f_n = 40z)
            when "10"   => return 8;  -- r = 16 (f_n = 20z)
            when others => return 16; -- r = 32 (f_n =10hz)
			
        end case;
    end function;

    signal cuenta   : integer range 0 to DIV_FS-1 := 0;
    signal n_semi   : integer range 0 to 15 := 0;
    signal sel_q    : std_logic_vector(1 downto 0) := "00";
    signal pulso    : std_logic := '0';
    signal latido_r : std_logic := '0';
    signal pert_r   : std_logic := '0';

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cuenta   <= 0;
                n_semi   <= 0;
                pulso    <= '0';
                latido_r <= '0';
                pert_r   <= '0';
                sel_q    <= sel;
            else
                sel_q <= sel;
                if cuenta = DIV_FS - 1 then
                    cuenta   <= 0;
                    pulso    <= '1'; -- instante de muestreo
                    latido_r <= not latido_r;
                else
                    cuenta <= cuenta + 1;
                    pulso  <= '0';
                    -- Desfase de medio periodo de muestreo antes del pulso fsclk
                    if cuenta = DIV_FS/2 - 1 then
                        if sel /= sel_q then
                            n_semi <= 0;
                        elsif n_semi = semiciclo(sel) - 1 then
                            n_semi <= 0;
                            pert_r <= not pert_r;
                        else
                            n_semi <= n_semi + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    fsclk  <= pulso;
    latido <= latido_r;
    pert   <= pert_r;

end architecture rtl;