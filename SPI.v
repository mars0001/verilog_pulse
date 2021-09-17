/*
	An implementation of a SPI slave that runs on the main clock.
	Inspired from here: https://www.fpga4fun.com/SPI2.html
*/
module SPI_slave (
	input			i_clk,
	input 			i_cs,
	input 			i_s_clk,
	input 			i_mosi,
	output   		o_spi_done,
	output [7:0] 	o_RX_byte
);

reg [7:0] r_data_reg;
reg [2:0] r_bit_count;
reg       r_done;	// set HIGH when the SPI transaction is finished

// de-mestability for SPI clock; double flopped and finding the rising edge
reg [2:0] r_sclk_dmt;
always @(posedge i_clk) begin
	r_sclk_dmt <= {r_sclk_dmt [1:0], i_s_clk};
end
wire w_sclk_rising_edge = (r_sclk_dmt[2:1] == 2'b01);

// de-mestability for SPI CS line; double flopped
reg [1:0] r_cs_dmt;
always @(posedge i_clk) begin
	r_cs_dmt <= {r_cs_dmt [0], i_cs};
end
wire w_cs_active = ~r_cs_dmt[1];	// CS is active low

// de-mestability for SPI MOSI line; double flopped
reg [1:0] r_mosi_dmt;
always @(posedge i_clk) begin
	r_mosi_dmt <= {r_mosi_dmt [0], i_mosi};
end
wire w_mosi_dmt = r_mosi_dmt[1];

// receiving the SPI data into a Shift register
always @(posedge i_clk) begin
	if(~w_cs_active) begin
		r_bit_count <= 3'b000; 
	end
	else if (w_sclk_rising_edge) begin
		r_bit_count <= r_bit_count + 3'b001;
		r_data_reg <= {r_data_reg[6:0], w_mosi_dmt};
	end
end

// assert the r_done signal HIGH when a SPI data byte was received
always @(posedge i_clk) begin
	r_done <= w_cs_active && w_sclk_rising_edge && (r_bit_count == 3'b111);
end

assign o_spi_done = r_done;
assign o_RX_byte = r_data_reg;

endmodule
