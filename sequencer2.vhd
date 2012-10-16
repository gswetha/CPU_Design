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
	
------------------------------------------------------------------
	procedure ROM_READ (addr: std_logic_vector(15 downto 0)) is
	begin
		i_rom_addr <= addr;
		i_rom_rd <= '1';
	end ROM_READ;
------------------------------------------------------------------
	procedure RAM_READ_BIT (addr: std_logic_vector(7 downto 0)) is
	begin
		i_ram_addr <= addr;
		i_ram_wrBit <= '0';
		i_ram_wrByte <= '0';
		i_ram_rdBit <= '1';
		i_ram_rdByte <= '0';
	end RAM_READ_BIT;
------------------------------------------------------------------
	procedure RAM_READ_BYTE (addr: std_logic_vector(7 downto 0)) is
	begin
		i_ram_addr <= addr;
		i_ram_wrBit <= '0';
		i_ram_wrByte <= '0';
		i_ram_rdBit <= '0';
		i_ram_rdByte <= '1';
	end RAM_READ_BYTE;
------------------------------------------------------------------
	procedure RAM_WRITE_BIT (addr: std_logic_vector(7 downto 0)) is
	begin
		i_ram_addr <= addr;
		i_ram_wrBit <= '1';
		i_ram_wrByte <= '0';
		i_ram_rdBit <= '0';
		i_ram_rdByte <= '0';
	end RAM_WRITE_BIT;
------------------------------------------------------------------
	procedure RAM_WRITE_BYTE (addr: std_logic_vector(7 downto 0)) is
	begin
		i_ram_addr <= addr;
		i_ram_wrBit <= '0';
		i_ram_wrByte <= '1';
		i_ram_rdBit <= '0';
		i_ram_rdByte <= '0';
	end RAM_WRITE_BYTE;
------------------------------------------------------------------
	
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
					end case;  -- exe_state of INC A
					
				--ACALL addr11
				when "00010001" | "00110001" | "01010001" | "01110001" | "10010001" | "10110001" | "11010001" | "11110001" =>
					case exe_state is
						when E0 =>
							ROM_READ(PC);  			--read PC(7 downto 0)
							RAM_READ_BYTE(x81);		--read data in sp
							exe_state <= E1;
							
					  when E1 =>
							PC <= PC + '1';
							AR <= i_rom_data;  		-- AR <= PC(7 downto 0) 
							DR <= i_ram_doByte;     -- sp 
							exe_state <= E2;
							
					  when E2 =>
							RAM_WRITE_BYTE(DR + '1');	--write PC(7 downto 0) into sp + 1 
							i_ram_diByte <= PC(7 downto 0);
							exe_state <= E3;
							
					  when E3 =>
							DR <= DR + '1';
							DR <= DR + '1';
							RAM_WRITE_BYTE(DR);	--write PC(15 downto 8) into sp + 2 
							i_ram_diByte <= PC(15 downto 8);		
							exe_state <= E4;
							
					  when E4 =>
							DR <= DR + '1';
							DR <= DR + '1';
							RAM_WRITE_BYTE(x81);
							i_ram_diByte <= DR;
							PC <= PC(15 downto 11) & IR(7 downto 5) & AR;	--PC(10 downto 0) <= page address
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
					  when others=>
					end case; --ACALL addr11
				
				--LCALL addr16
				when "00010010" =>
					
					case exe_state is
					
					  when E0 =>
							PC <= PC + '1';
							ROM_READ(PC);  	   --read PC(7 downto 0)
							RAM_READ_BYTE(x81);		--read data in sp
							PC <= PC + '1';
							PC <= PC + '1';
							
							exe_state <= E1;
							
					  when E1 =>
							PC <= PC - '1';
							PC <= PC - '1';
							ROM_READ(PC);			--read PC(15 downto 8)
							RAM_WRITE_BYTE(i_ram_doByte + '1'); --write (PC + 2)(7 downto 0) to sp+1
							i_ram_diByte <= PC(7 downto 0);
							DR <= i_rom_data;  -- write PC(7 downto 0) to dr
							AR <= i_ram_doByte; -- sp 
							
							exe_state <= E2;
							
					  when E2 =>
							AR <= AR + '1';
							AR <= AR + '1';
							RAM_WRITE_BYTE(AR);     --write (PC + 2)(15 downto 8) into sp + 2
							i_ram_diByte <= PC(15 downto 8);
							PC <= i_rom_data & DR;
							
							exe_state <= E3;
							
					  when E3 =>
							AR <= AR + '1';
							AR <= AR + '1';
							RAM_WRITE_BYTE(x81);				--write sp + 2 into sp 
							i_ram_diByte <= AR;		
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
					  when others=>
					end case; --LCALL addr16
				
				--RET
				when "00100010" =>					
					case exe_state is
					
					  when E0 =>
							RAM_READ_BYTE(x81);		--read data in sp,
							
							exe_state <= E1;
							
					  when E1 =>
							RAM_READ_BYTE(i_ram_doByte);
							DR <= i_ram_doByte;		--addr of top stack
							
							exe_state <= E2;
							
					  when E2 =>
							RAM_READ_BYTE(DR - '1');
							PC(15 downto 8) <= i_ram_doByte;	--pop the top stack
							
							exe_state <= E3;
							
					  when E3 =>
							DR <= DR - '1';
							DR <= DR - '1';
							RAM_WRITE_BYTE(x81);
							i_ram_diByte <= DR;	--pop the 2nd of the stack
							PC(7 downto 0) <= i_ram_doByte;
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
					  when others=>
					end case; --RET
				
				--RETI					
				when "00110010" =>
					
					case exe_state is
					
					  when E0 =>
							RAM_READ_BYTE(x81);		--read data in sp
							
							exe_state <= E1;
							
					  when E1 =>
							RAM_READ_BYTE(i_ram_doByte);
							DR <= i_ram_doByte;
							
							exe_state <= E2;
							
					  when E2 =>
							RAM_READ_BYTE(DR - '1');	--pop top of stack
							PC(15 downto 8) <= i_ram_doByte;
							
							exe_state <= E3;
							
					  when E3 =>
							DR <= DR - '1';
							DR <= DR - '1';
							RAM_WRITE_BYTE(x81);
							i_ram_diByte <= DR;	--pop 2nd of stack
							PC(7 downto 0) <= i_ram_doByte;
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
					  when others=>
					end case; --RETI
				
				--AJMP addr11				
				when "00000001" | "00100001" | "01000001" | "01100001" | "10000001" | "10100001" | "11000001" | "11100001" =>
					case exe_state is
					
						when E0 =>
							ROM_READ(PC);
							
							exe_state <= E1;
							
						when E1 =>
							PC <= PC + '1';
							AR <= i_rom_data;
							
							exe_state <= E2;
							
						when E2 =>
							PC <= PC(15 downto 11) & IR(7 downto 5) & AR;	--(PC10-0) <- page address
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
						when others=>
					end case; --AJMP addr11
				
				--LJMP addr16				
				when "00000010" =>
					
					case exe_state is
					
						when E0 =>
							ROM_READ(PC);
							
							exe_state <= E1;
							
						when E1 =>
							ROM_READ(PC + '1');
							AR <= i_rom_data;
							
							exe_state <= E2;
							
						when E2 =>
							PC <= AR & i_rom_data;  
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
						when others=>
					end case; --LJMP addr16
				
				--SJMP rel
				when "10000000" =>
					
					case exe_state is
					
						when E0 =>
							ROM_READ(PC);
							
							exe_state <= E1;
							
						when E1 => 
							
							if i_rom_data(7) = '1' then
								alu_src_2L <= PC(7 downto 0);
								alu_src_2H <= PC(15 downto 8);	
								alu_src_1L <= i_rom_data;
								alu_src_1H <= "11111111";	
								alu_op_code <= ALU_OPC_ADD;
								alu_cy_bw <= '0';
								alu_by_wd <= '1';
							
							else
								alu_src_2L <= PC(7 downto 0);
								alu_src_2H <= PC(15 downto 8);	
								alu_src_1L <= i_rom_data;
								alu_src_1H <= "00000000";	
								alu_op_code <= ALU_OPC_ADD;
								alu_cy_bw <= '0';
								alu_by_wd <= '1';
								
							end if;
							
							exe_state <= E2;
							
						when E2 =>
						   PC <= alu_ans_H & alu_ans_L;
							
							exe_state <= E3;
							
						when E3 =>
						   PC <= PC + '1';
							
							exe_state <= E0;	
							cpu_state <= T0;	
							
						when others=>
					end case; --SJMP rel
				
				--JMP @A + DPTR	
				when "01110011"  =>
					case exe_state is
					
						when E0 =>
							RAM_READ_BYTE(x83); --read dph
							
							exe_state <= E1;
							
						when E1 =>
							DR <= i_ram_doByte;
							RAM_READ_BYTE(x82); --read dpl
							
							exe_state <= E2;
							
						when E2 =>
						   AR <= i_ram_doByte;
							RAM_READ_BYTE(xE0); --read acc
								
							exe_state <= E3;
							
						when E3 =>
							alu_src_2L <= AR;
							alu_src_2H <= DR;	
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_ADD;
							alu_cy_bw <= '0';
							alu_by_wd <= '1';
							
							exe_state <= E4;
							
						when E4 =>
							PC <= alu_ans_H & alu_ans_L;
												
							exe_state <= E0;	
							cpu_state <= T0;	
							
						when others=>					
					end case; --JMP @A + DPTR
				
				--JZ rel
				WHEN "01100000" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XE0);	--read in acc
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							if( I_RAM_DOBYTE = "00000000" ) then	--check in acc is 0
                                if(i_rom_data(7) = '0') then
									PC <= PC + i_rom_data(6 downto 0);
								else 
									PC <= PC - not(i_rom_data(6 downto 0)) - 1;	--negative so convert to 1 complement
								end if;
                            end if;	
									
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						WHEN OTHERS	=>
				END CASE;	--jz rel
				
				--JNZ rel			--ZhenYong, Tested and simulated.
				WHEN "01110000" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XE0);
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							if( I_RAM_DOBYTE /= "00000000" ) then
                                if(i_rom_data(7) = '0') then
									PC <= PC + i_rom_data(6 downto 0);
								else 
									PC <= PC - not(i_rom_data(6 downto 0)) - 1;
								end if;
                            end if;	
									
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						WHEN OTHERS	=>
					END CASE;	--jnz rel
				
				--CJNE A,direct,rel
				WHEN "10110101" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XE0);
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							DR <= I_RAM_DOBYTE; --ACC
							ROM_READ(PC);
							RAM_READ_BYTE(i_rom_data);--direct addressed data
							PC <= PC + '1';
									
							EXE_STATE <= E2;
						WHEN E2	=>
							RAM_READ_BYTE(XD0); --read psw
							if( I_RAM_DOBYTE /= DR ) then
								if(i_rom_data(7) = '0') then
									PC <= PC + i_rom_data(6 downto 0);
								else 
									PC <= PC - not(i_rom_data(6 downto 0)) - 1;
								end if;
                            end if;
									
							EXE_STATE <= E3;
						WHEN E3	=>
							
							if( DR < I_RAM_DOBYTE ) then
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '1' & I_RAM_DOBYTE(6 downto 0);
							else
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '0' & I_RAM_DOBYTE(6 downto 0);
							end if;
							
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						
						WHEN OTHERS	=>
					END CASE;		--CJNE A,direct,rel
					
				--CJNE A,#data,rel
				WHEN "10110100" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XD0); --PSW
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							AR <= I_RAM_DOBYTE; --PSW
							DR <= i_rom_data; --#data
							RAM_READ_BYTE(XE0); --ACC
							ROM_READ(PC);
							PC <= PC + '1';
									
							EXE_STATE <= E2;
						WHEN E2	=>
							if( DR /= I_RAM_DOBYTE ) then
								if(i_rom_data(7) = '0') then
									PC <= PC + i_rom_data(6 downto 0);
								else 
									PC <= PC - not(i_rom_data(6 downto 0)) - 1;
								end if;
                            end if;
									
							EXE_STATE <= E3;
						WHEN E3	=>
							
							if( I_RAM_DOBYTE < DR ) then
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '1' & AR(6 downto 0);
							else
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '0' & AR(6 downto 0);
							end if;
		
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						
						WHEN OTHERS	=>
					END CASE;	--CJNE A,#data,rel
					
				--CJNE Rn,#data,rel
				WHEN "10111000" | "10111001" | "10111010" | "10111011" | "10111100" | "10111101" | "10111110" | "10111111" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XD0); --PSW
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							AR <= I_RAM_DOBYTE; --PSW
							DR <= i_rom_data; --#data
							RAM_READ_BYTE("000" & i_ram_doByte(4 downto 3) &  IR(2 downto 0)); --@Ri
							ROM_READ(PC);
							PC <= PC + '1';
									
							EXE_STATE <= E2;
						WHEN E2	=>
							if( DR /= I_RAM_DOBYTE ) then
								if(i_rom_data(7) = '0') then
									PC <= PC + i_rom_data(6 downto 0);
								else 
									PC <= PC - not(i_rom_data(6 downto 0)) - 1;	--negative
								end if;
                            end if;
									
							EXE_STATE <= E3;
						WHEN E3	=>
							
							if( I_RAM_DOBYTE < DR ) then
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '1' & AR(6 downto 0);
							else
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '0' & AR(6 downto 0);
							end if;
							
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						
						WHEN OTHERS	=>
					END CASE;	--CJNE Rn,#data,rel
					
				--CJNE @Ri,#data,rel
				WHEN "10110110" | "10110111" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XD0); --PSW
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							AR <= I_RAM_DOBYTE; --PSW
							DR <= i_rom_data; --#data
							RAM_READ_BYTE("000" & i_ram_doByte(4 downto 3) & "00" & IR(0)); --@Ri
									
							EXE_STATE <= E2;
						
						WHEN E2 =>
							RAM_READ_BYTE(I_RAM_DOBYTE);
							ROM_READ(PC);
							PC <= PC + '1';
							
							EXE_STATE <= E3;
							
						WHEN E3	=>
							if( DR /= I_RAM_DOBYTE ) then
								if(i_rom_data(7) = '0') then
									PC <= PC + i_rom_data(6 downto 0);
								else 
									PC <= PC - not(i_rom_data(6 downto 0)) - 1;	--negative
								end if;
                            end if;
									
							EXE_STATE <= E4;
						WHEN E4	=>
							
							if( I_RAM_DOBYTE < DR ) then
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '1' & AR(6 downto 0);
							else
								RAM_WRITE_BYTE(xD0);
								i_ram_diByte <= '0' & AR(6 downto 0);
							end if;
							
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						
						WHEN OTHERS	=>
					END CASE;	--CJNE @Ri,#data,rel
					
				--DJNZ Rn,rel
				WHEN "11011000" | "11011001" | "11011010" | "11011011" | "11011100" | "11011101" | "11011110" | "11011111" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							RAM_READ_BYTE(XD0); --PSW
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							DR <= i_rom_data; --rel
							RAM_READ_BYTE("000" & i_ram_doByte(4 downto 3) & IR(2 downto 0)); --Rn
							AR <= "000" & i_ram_doByte(4 downto 3) & IR(2 downto 0);
									
							EXE_STATE <= E2;
						when E2	=>
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_DEC;	
							alu_by_wd <= BYTE;
							
							exe_state <= E3;
						WHEN E3	=>
							if( alu_ans_L /= "00000000" ) then
								if(DR(7) = '0') then
									PC <= PC + DR(6 downto 0);
								else 
									PC <= PC - not(DR(6 downto 0)) - 1;	--negative
								end if;
                            end if;
							
							i_ram_diByte <= alu_ans_L;
							RAM_WRITE_BYTE(AR);

							CPU_STATE <= T0;
							EXE_STATE <= E0;

						WHEN OTHERS	=>
					END CASE;	--DJNZ Rn,rel
					
				--DJNZ direct,rel
				WHEN "11010101" =>
					CASE EXE_STATE IS
						WHEN E0	=>
							ROM_READ(PC);
							PC <= PC + '1';
									
							EXE_STATE <= E1;
						WHEN E1	=>
							ROM_READ(PC);
							PC <= PC + '1';
							RAM_READ_BYTE(i_rom_data); --dir
							AR <= i_rom_data;
									
							EXE_STATE <= E2;
						when E2	=>
							DR <= i_rom_data; --rel
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_DEC;	
							alu_by_wd <= BYTE;
							exe_state <= E3;
						WHEN E3	=>
							if( alu_ans_L /= "00000000" ) then
								if(DR(7) = '0') then
									PC <= PC + DR(6 downto 0);
								else 
									PC <= PC - not(DR(6 downto 0)) - 1;	--negative
								end if;
                            end if;
							
							i_ram_diByte <= alu_ans_L;
							RAM_WRITE_BYTE(AR);
							
							CPU_STATE <= T0;
							EXE_STATE <= E0;
						
						WHEN OTHERS	=>
					END CASE;	--DJNZ direct,rel
					
				-- INC Rn
				when "00001000" | "00001001" | "00001010" | "00001011" | "00001100" | "00001101" | "00001110" | "00001111" =>
					case exe_state is
						when E0	=>
							RAM_READ_BYTE(xD0);	--psw
									
							exe_state <= E1;
						when E1	=>
							AR <= "000" & i_ram_doByte(4 downto 3) & IR(2 downto 0);
							RAM_READ_BYTE("000" & i_ram_doByte(4 downto 3) & IR(2 downto 0));
									
							exe_state <= E2;
						when E2	=>	
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_INC;	
							alu_by_wd <= BYTE;
							
							exe_state <= E3;
						when E3	=>
							RAM_WRITE_BYTE(AR);
							i_ram_diByte <= alu_ans_L;	
							
							cpu_state <= T0;
							exe_state <= E0;
						when others	=>
					end case;	--inc rn
				
				-- INC direct
				when "00000101" =>
					case exe_state is
						when E0	=>
							ROM_READ(PC);
							PC <= PC + '1';
									
							exe_state <= E1;
						when E1	=>
							RAM_READ_BYTE(i_rom_data);
							AR <= i_rom_data;
									
							exe_state <= E2;
						when E2	=>
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_INC;
							alu_by_wd <= BYTE;
							
							exe_state <= E3;
						when E3	=>
							RAM_WRITE_BYTE(AR);
							i_ram_diByte <= alu_ans_L;	
							
							cpu_state <= T0;
							exe_state <= E0;
						when others	=>
					end case;	--inc direct
				
				-- INC @Ri
				when "00000110" | "00000111" =>
					case exe_state is
						when E0	=>
							RAM_READ_BYTE(xD0);	--psw
									
							exe_state <= E1;
						when E1	=>
							RAM_READ_BYTE("000" & i_ram_doByte(4 downto 3) & "00" & IR(0));
									
							exe_state <= E2;
						
						when E2 =>
							AR <= i_ram_doByte;
							RAM_READ_BYTE(i_ram_doByte);
							
							exe_state <= E3;
									
						when E3	=>
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_INC;	
							alu_by_wd <= BYTE;
							
							exe_state <= E4;
						when E4	=>
							RAM_WRITE_BYTE(AR);
							i_ram_diByte <= alu_ans_L;	
							
							cpu_state <= T0;
							exe_state <= E0;
						when others	=>
					end case;	-- INC @Ri
				
				-- INC DPTR
				when "10100011" =>
					case exe_state is
						when E0	=>
							RAM_READ_BYTE(x82);	--dpl
									
							exe_state <= E1;					
						when E1	=>	
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_INC;	
							alu_by_wd <= BYTE;
							
							RAM_READ_BYTE(x83);	--dph
							exe_state <= E2;
						when E2	=>	
							RAM_WRITE_BYTE(x82);
							i_ram_diByte <= alu_ans_L;
							
							alu_src_1L <= i_ram_doByte;
							alu_src_1H <= "00000000";	
							alu_op_code <= ALU_OPC_INC;
							alu_by_wd <= BYTE;
							
							exe_state <= E3;	
						when E3	=>
							RAM_WRITE_BYTE(x83);
							i_ram_diByte <= alu_ans_L;	
							
							cpu_state <= T0;
							exe_state <= E0;
						when others	=>
					end case;	---- INC DPTR
					
	



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
