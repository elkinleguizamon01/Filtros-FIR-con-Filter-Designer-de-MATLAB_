library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bin_a_bcd is
    port (
        bin_in  : in  std_logic_vector(11 downto 0);
        bcd_out : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of bin_a_bcd is
begin
    process(bin_in)
        variable temp : integer range 0 to 4095;
    begin
        temp := to_integer(unsigned(bin_in));
        bcd_out(3 downto 0)   <= std_logic_vector(to_unsigned(temp mod 10, 4));
        bcd_out(7 downto 4)   <= std_logic_vector(to_unsigned((temp/10) mod 10, 4));
        bcd_out(11 downto 8)  <= std_logic_vector(to_unsigned((temp/100) mod 10, 4));
        bcd_out(15 downto 12) <= std_logic_vector(to_unsigned((temp/1000) mod 10, 4));
    end process;
end architecture;