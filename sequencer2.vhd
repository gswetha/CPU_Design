library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;

entity sequencer2 is
    port(
		rst                : in  std_logic;
		clk              	 : in  std_logic;
		ale		  	 : out std_logic;
		psen		 	 : out std_logic;

		alu_op_code	 	 : out  std_logic_vector (3 downto 0);
		alu_src_1L		 : out  std_logic_vector (7 downto 0);
		alu_src_1H		 : out  std_logic_vector (7 downto 0);
		alu_src_2L		 : out  std_logic_vector (7 downto 0);
		alu_src_2H		 : out  std_logic_vector (7 downto 0);
		alu_by_wd		 : out  std_logic;             -- byte(0)/word(1) instruction
		alu_cy_bw		 : out  std_logic;             -- carry/borrow bit
		alu_ans_L		 : in std_logic_vector (7 downto 0);
		alu_ans_H		 : in std_logic_vector (7 downto 0);
		alu_cy		 	 : in std_logic;             -- carry out of bit 7/15
		alu_ac		 	 : in std_logic;		    -- carry out of bit 3/7
		alu_ov		 	 : in std_logic;		    -- overflow

		dividend_i		 : out  std_logic_vector(15 downto 0);
		divisor_i		 : out  std_logic_vector(15 downto 0);
		quotient_o		 : in std_logic_vector(15 downto 0); 
		remainder_o	 	 : in std_logic_vector(15 downto 0);
		div_done		 : in std_logic ;

		mul_a_i		 	 : out  std_logic_vector(15 downto 0);  -- Multiplicand
		mul_b_i		 	 : out  std_logic_vector(15 downto 0);  -- Multiplicator
		mul_prod_o 	 	 : in std_logic_vector(31 downto 0) ;-- Product

		i_ram_wrByte   	 : out std_logic; 
		i_ram_wrBit   	 : out std_logic; 
		i_ram_rdByte   	 : out std_logic; 
		i_ram_rdBit   	 : out std_logic; 
		i_ram_addr 	 	 : out std_logic_vector(7 downto 0); 
		i_ram_diByte  	 : out std_logic_vector(7 downto 0); 
		i_ram_diBit   	 : out std_logic; 
		i_ram_doByte   	 : in std_logic_vector(7 downto 0); 
		i_ram_doBit   	 : in std_logic; 
		
		i_rom_addr       : out std_logic_vector (15 downto 0);
		i_rom_data       : in  std_logic_vector (7 downto 0);
		i_rom_rd         : out std_logic;
		
		pc_debug	 	 : out std_logic_vector (15 downto 0);
		interrupt_flag	 : in  std_logic_vector (2 downto 0);
		erase_flag	 : out std_logic);

end sequencer2;

-------------------------------------------------------------------------------

architecture seq_arch of sequencer2 is

    type t_cpu_state is (T0, T1, I0); --these determine whether you are in initialisation, state, normal execution state, etc
    type t_exe_state is (E0, E1, E2, E3, E4, E5, E6, E7, E8, E9, E10); --these are the equivalence T0, T1 in the lecture
    
	signal cpu_state 		: t_cpu_state;
    	signal exe_state 		: t_exe_state;
    	signal IR				: std_logic_vector(7 downto 0);		-- Instruction Register
	signal PC				: std_logic_vector(15 downto 0);	-- Program Counter
	signal AR				: std_logic_vector(7 downto 0);		-- Address Register
	signal DR				: std_logic_vector(7 downto 0);		-- Data Register
	signal int_hold			: std_logic;

begin

    process(rst, clk)
    begin
    if( rst = '1' ) then
   	cpu_state <= T0;
    exe_state <= E0;
	ale <= '0'; psen <= '0';
	mul_a_i <= (others => '0'); mul_b_i <= (others => '0');
	dividend_i <= (others => '0'); divisor_i <= (others => '1');
	i_ram_wrByte <= '0'; i_ram_rdByte <= '0'; i_ram_wrBit <= '0'; i_ram_rdBit <= '0';
	IR <= (others => '0');-- instruction register - where u get the instruction from
	PC <= (others => '0');-- PC counter, increment 12345678
	--PC <= "0000000000100111";
	AR <= (others => '0');
	DR <= (others => '0');
	pc_debug <= (others => '1');
	int_hold <= '0';
	erase_flag <= '0';	
    elsif (clk'event and clk = '1') then
    case cpu_state is
		when T0 => --fetch
			--get instruction from ROM and load it IR
			case exe_state is
				when E0	=>	--clock cycle 0
					i_rom_addr <= PC;
					i_rom_rd <= '1';
					exe_state <= E1;
							
				when E1	=> 	--clock cycle 1
					-- load instruction add. into IR
					IR <= i_rom_data;	
					cpu_state <= T1;
					PC <= PC + '1';
					exe_state <= E0;
					
				when others =>	  
			end case; -- exe_state 

		when T1 =>   --execute
			case IR is 
				
				-- NOP
				when "00000000"  =>
					case exe_state is
						when E0	=> 
							
							exe_state <= E1;
						
						when E1	=>
							exe_state <= E2;
							
						when E2	=>						
							exe_state <= E0;
							cpu_state <= T0; -- needs to go back to rom and fetch new instruction	
						when others =>
					end case;  -- exe_state of NOP
				--CLR A
				when "11100100" =>
					case exe_state is
						when E0	=>  
						   i_ram_addr <= xE0;
							i_ram_diByte <= "00000000";
							i_ram_wrByte <= '1';
							exe_state <= E1;
						
						when E1	=>
						   i_ram_wrByte <= '0'; -- reset writebyte to 0
							exe_state <= E2;
							
						when E2	=>						
							exe_state <= E0;
							cpu_state <= T0; 
						when others =>
					end case;  -- exe_state of CLR A
				-- MOV A,data
					when "01110100" =>
					case exe_state is
						when E0	=>  
							i_rom_addr <= PC;
							i_rom_rd <= '1';
							exe_state <= E1;
												
						when E1	=>
						   i_ram_diByte <= i_rom_data;
							i_ram_addr <= xE0;
							i_ram_wrByte <= '1';
							exe_state <= E2;
							
											
						when E2	=>		
							i_ram_wrByte <= '0';	
							PC <= PC + '1';	
							i_rom_rd <= '0';	
							exe_state <= E0;
							cpu_state <= T0; 
						when others =>
					end case;  -- exe_state of MOV A,data
		
				--INC A
				when "00000100" =>
					case exe_state is
						when E0	=>  
						   i_ram_addr <= xE0;
							i_ram_rdByte <='1';
							exe_state <= E1;
						
						when E1	=>
						   i_ram_rdByte <= '0';
						   i_ram_diByte <= i_ram_doByte + '1'; 
						   
							exe_state <= E2;
							
						when E2	=>	
						   i_ram_wrByte <= '1';	
					
							exe_state <= E3;
						
						when E3 =>
            			i_ram_wrByte <= '0'; -- reset writebyte to 0
				
							exe_state <= E0;
							cpu_state <= T0; 
						when others =>
					end case;  -- exe_state of CLR A
					
	



			when others => 		
					exe_state <= E0;	
					cpu_state <= T0;
			end case; -- IR
    when I0 => -- interrupt
	end case; --cpu_state
end if;
end process;
end seq_arch;

-------------------------------------------------------------------------------

-- end of file --
