module SPI_slave (
	input 			i_cs,
	input 			i_s_clk,
	input 			i_mosi,
	output   		o_Done,
	output [7:0] 	o_RX_byte
);

reg [7:0] r_data_reg;
reg [3:0] r_index_bit;
reg       r_Done = 1'b0;	// set HIGH when the SPI transaction is finished

always @(posedge i_s_clk) begin
	
	if(!i_cs) begin
		r_data_reg = {r_data_reg[6:0], i_mosi};
		r_index_bit = r_index_bit + 4'b1;
		if (r_index_bit != 8) begin
			r_Done = 0;
		end
		else begin
			r_Done = 1;
			r_index_bit = 4'b0;
		end
	end
end

assign o_Done = r_Done;
assign o_RX_byte = r_data_reg;

endmodule