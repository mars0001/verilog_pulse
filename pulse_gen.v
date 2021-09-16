/*
	The desired function is to create a configurable pulse for which we need to 
	configure the HIGH time and the LOW time. A PWM module.
	We control the pulse generation with the start_nstop signal:
		start_nstop = HIGH -> system is enabled
		start_nstop = LOW -> system is disabled
	
	Even if we start the system with the start_nstop signal, it will not actually
	start until it does not receive, via a multiple SPI transaction (8 bytes), 
	a configuration word made of 64 bits.

	The top 24 bits are the pulse HIGH duration and the last 40 bits are the 
	pulse LOW duration in the sense that those 2 numbers are multiple of the clock
	period, i_clk. MSB to LSB.
	I am going to use a 20ns (50MHz) period i_clk clock.
	
	The i-reset signal will reset the system to the state where it waits for the
	configuration word followed by the start_nstop signal toggled to HIGH.
	The configuration word needs to be sent only once after the power-up.

	In order to catch all SPI transactions I am going to use a i_spi_clk (SPI clock)
	of maximum 8MHz. That should allow a lot of clock edges to evaluate signals comming 
	from the SPI module. Which means that we will require mX 8 uS for each 
	64-bit configuration word that is received.
*/

module pulse_gen (
	input 	i_clk,			// system clock
    input 	i_reset,		// control signal, will reset the system in waiting for configuration word
	input 	i_spi_clk,		// SPI clock
	input 	i_spi_nCS,		// SPI chip select, active LOW
	input 	i_spi_mosi,		// SPI data input
	input 	start_nstop,	// strobe signal that control if the system is working
	output 	o_led,			// pulse output
	output	o_activity		// show if the system is active
);

// machine state states
localparam IDLE         		= 3'b000;
localparam RECEIVE_CONF_BITS	= 3'b001;
// localparam WAIT_NEXT_BYTE		= 3'b010;
localparam RUN  				= 3'b011;
localparam PULSE_HIGH			= 3'b100;
localparam PULSE_LOW  			= 3'b101;
localparam RESET  				= 3'b110;

wire        w_done;			// flag that the SPI has received a new byte
wire [7:0]  w_spi_byte;		// the byte recevied on SPI interface

/*
	Store 40 bits of configuration, received through SPI.
*/
reg [63:0]  r_conf = 64'b0;				// register for configuration bits storage
reg [2:0]   r_index_conf_bytes = 3'b0;	// configuration byte counter
reg 		r_conf_received = 1'b0;		// flag that all 8 configuration bytes arrived

reg[2:0]	r_spi_done_dmt;

// counter while the output o_led is LOW
reg [39:0]	r_pause_count = 40'b0;
// counter while the output o_led is HIGH
reg [23:0]	r_pulse_count = 24'b0;

reg 		r_led;		// the pulse output intermediate storage

// state machine
reg [2:0]   r_SM_Main = IDLE;
reg [2:0]	r_prev_SM_state = IDLE;

// instantiation of SPI receiver module
SPI_slave my_spi (
	.i_cs (i_spi_nCS),
	.i_s_clk (i_spi_clk),
	.i_mosi (i_spi_mosi),
	.o_Done (w_done),
	.o_RX_byte (w_spi_byte)
);

// de-metastability for SPI done signal
always @(posedge i_clk) begin
	r_spi_done_dmt <= {r_spi_done_dmt[1:0], w_done};
end

// falling edge for the signal so we have a new SPI byte that is process of being received
// wire w_spi_in_progress_dmt = (r_spi_done_dmt[2:1] == 2'b10);
// rising edge for the signal so we have a new SPI byte that was received
wire w_spi_done_dmt = (r_spi_done_dmt[2:1] == 2'b01);

always @(posedge i_clk) begin
	case(r_SM_Main)
		// state before receiving the configuration and also the ENTRY state after power up
		IDLE: begin
			// if we have received a CONFIGURATION word ...
			if (r_conf_received) begin
				r_prev_SM_state <= PULSE_LOW;	// start with the pulse HIGH
				r_SM_Main <= RUN;				// go to the RUN state
			end 
			else begin
				// init the configuration word and the configuration byte counter
				r_index_conf_bytes <= 3'b0;
				r_conf <= 64'b0;
				r_SM_Main <= RECEIVE_CONF_BITS;	// no CONFIG bits, go to the RECEIVE_CONF_BITS state
			end
		end

		// state in which we receive all 40 bits of configuration (5 bytes)
		RECEIVE_CONF_BITS: begin
			// if a byte was received by the SPI
			if (w_spi_done_dmt) begin
				
				// concatenate the received SPI byte to the CONF storage register
				r_conf <= {r_conf[55:0], w_spi_byte};

				// if we received all 8 bytes go to the IDLE state and tell that the 
				// configuration word was received
				if (r_index_conf_bytes == 3'b111) begin
					r_index_conf_bytes <= 3'b0;
					r_conf_received <= 1'b1;
					r_SM_Main <= IDLE;
				end
				else begin
					// count the received bytes
					r_index_conf_bytes <= r_index_conf_bytes + 3'b1;

					// if we didn't recevied all the configuration bytes wait for the next
					// byte by going to the WAIT_NEXT_BYTE state
					// r_SM_Main <= WAIT_NEXT_BYTE;
				end
			end
		end

		// WAIT_NEXT_BYTE: begin
		// 	// go back to the RECEIVE_CONF_BITS state only when a new byte started
		// 	// to be SPI received
		// 	if (w_spi_in_progress_dmt) begin
		// 		r_SM_Main <= RECEIVE_CONF_BITS;
		// 	end
		// end

		// state where we have the configuration bits and the pulses are
		// running
		RUN: begin
			// alternate HIGH/LOW levels according to the configuration
			if (start_nstop) begin
				if (r_prev_SM_state == PULSE_HIGH) begin
					r_pause_count <= 40'b0;
					r_SM_Main <= PULSE_LOW;
				end
				else if (r_prev_SM_state == PULSE_LOW) begin
					r_pulse_count <= 24'b0;
					r_SM_Main <= PULSE_HIGH;
				end
			end
			else begin
				r_led <= 1'b0;
				r_SM_Main <= RUN;
			end

			// if the system is reset go to the RESET state
			if (i_reset == 0) begin
				r_SM_Main <= RESET;
			end
		end

		// creates a pulse HIGH on the o_led output
		PULSE_HIGH: begin
			r_led <= 1;
			r_prev_SM_state <= PULSE_HIGH;

			// abort if the input start_nstop is LOW
			if (!start_nstop) begin
				r_led <= 0;
				r_SM_Main <= RUN;
			end
			// upper 24 bits configure the pulse HIGH duration
			else if (r_pulse_count == r_conf[63:40]) begin
				r_SM_Main <= RUN;
			end
			else begin
				r_pulse_count <= r_pulse_count + 24'b1;
			end
		end

		// delay between any two pulses, the o_led output is LOW
		PULSE_LOW: begin
			r_led <= 0;
			r_prev_SM_state <= PULSE_LOW;

			// abort if the input start_nstop is LOW
			if (!start_nstop) begin
				r_SM_Main <= RUN;
			end
			// lower 40 bits configure the pulse LOW duration
			else if (r_pause_count == r_conf[39:0]) begin
				r_SM_Main <= RUN;
			end
			else begin
				r_pause_count <= r_pause_count + 40'b1;
			end
		end

		// RESET the system and then go to the IDLE state to wait for a configuration word
		RESET: begin
			r_led <= 1'b0;
			r_conf <= 64'b0;
			r_conf_received <= 1'b0;
			r_index_conf_bytes <= 3'b0;
			r_pause_count <= 40'b0;
			r_pulse_count <= 24'b0;

			r_SM_Main <= IDLE;
		end
	endcase
end

assign o_led = r_led;
assign o_activity = start_nstop;

endmodule