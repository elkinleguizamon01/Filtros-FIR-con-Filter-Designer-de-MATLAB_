library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bin_a_bcd is
    port (
        bin_i      : in  std_logic_vector(11 downto 0);
        centenas_o : out std_logic_vector(3 downto 0);
        decenas_o  : out std_logic_vector(3 downto 0);
        unidades_o : out std_logic_vector(3 downto 0)
    );
end entity bin_a_bcd;

architecture rtl of bin_a_bcd is
begin

    process (bin_i)
        variable temp : unsigned(11 downto 0);
        variable bcd  : unsigned(11 downto 0);
    begin
        bcd  := (others => '0');
        temp := unsigned(bin_i);

        for i in 0 to 11 loop
            if bcd(3 downto 0) >= 5 then
                bcd(3 downto 0) := bcd(3 downto 0) + 3;
            end if;
            if bcd(7 downto 4) >= 5 then
                bcd(7 downto 4) := bcd(7 downto 4) + 3;
            end if;
            if bcd(11 downto 8) >= 5 then
                bcd(11 downto 8) := bcd(11 downto 8) + 3;
            end if;

            bcd  := bcd(10 downto 0) & temp(11);
            temp := temp(10 downto 0) & '0';
        end loop;

        centenas_o <= std_logic_vector(bcd(11 downto 8));
        decenas_o  <= std_logic_vector(bcd(7 downto 4));
        unidades_o <= std_logic_vector(bcd(3 downto 0));
    end process;

end architecture rtl;