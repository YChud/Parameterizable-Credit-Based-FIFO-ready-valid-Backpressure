module fifo #(
  parameter int Data_W = 32, //The data will be 32 bits
  parameter int DEPTH = 8, //We will have 8 places to store memory
  parameter int PIPE_OUT = 0, //Toggle on and off the PIPE_OUT mode
  parameter int SKID_EN = 0 //Toggle on and off the SKID buffer
)(
  
  //Clock initlization
  input logic clk,
  input logic rst_n,
  
  //Source->FIFO
  input logic s_valid,
  output logic s_ready,
  input logic [Data_W-1:0] s_data,
  
  //FIFO->Sink
  output logic m_valid,
  input logic m_ready,
  output logic [Data_W-1:0] m_data,
  
  //Debugging parameters
  output logic [$clog2(DEPTH+1)-1:0] level,
  output logic empty,
  output logic full,
  output logic [$clog2(DEPTH+1)-1:0] credits
  
);
  
  //Memory for the FIFO
  //8 Memory slots each holding 32 bits
  logic [Data_W-1:0] mem [0:DEPTH-1];
  
  //Helping me dynamically change the bit amount based on DEPTH
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  
  //Initializing the pointers
  logic [PTR_W-1:0] wr_ptr;
  logic [PTR_W-1:0] rd_ptr;
  
  //Defining the pop and push functions
  logic push;
  logic pop;
  
  logic stall_prev;
  logic [Data_W-1:0] m_data_prev;
  
  //Logic for PIPE_OUT function
  logic pipe_valid;
  logic [Data_W-1:0] pipe_data;
  logic signed [$clog2(DEPTH+1):0] level_next;
  logic [PTR_W-1:0] rd_ptr_next;
  
  
  //Logic for SKID
  logic core_valid;
  logic [Data_W-1:0] core_data;
  logic core_ready;
  logic skid_valid;
  logic [Data_W-1:0] skid_data;
  
  always @(posedge clk) begin
    
    //Reset logic
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      level <= '0;
      m_data_prev <= '0;
      stall_prev  <= 1'b0;
    end else begin
      
      
      //Push logic: Writing data into FIFO
      if (push) begin
        mem[wr_ptr]<=s_data;
      end
      
      //Push logic: Updating the wr_ptr
      if (push) begin
        if (wr_ptr == PTR_W'(DEPTH-1))
          wr_ptr<= '0;
        else
          wr_ptr <= wr_ptr + 1'b1;
      end
      
      //Pop logic: Because of the assign below 
      //m_data automatically gets updated
      
      //Pop logic: Updating the rd_ptr
      if (pop) begin
        if (rd_ptr == PTR_W'(DEPTH-1))
          rd_ptr <= '0;
        else
          rd_ptr <= rd_ptr + 1'b1;
      end
      
      case ({push, pop})
        2'b10: level <= level + 1'b1; // push only
        2'b01: level <= level - 1'b1; // pop only
        default: level <= level;      // 00 or 11 (no change)
      endcase
      
      
      //Assertions:
      // 1) No overflow: if full, must not be ready
      assert (!(full && push && !pop)) //this can't happen
        else $fatal(1, "FIFO overflow: full=1 but accepted push");

      // 2) No underflow: if empty, must not be valid
      assert (!(empty && !PIPE_OUT && core_valid))
      else $fatal(1, "FIFO underflow: empty=1 but core_valid=1");
      
      // 3) Data saves when there is backpressure
      // If we were stalled last cycle, then data must be stable now
      if (stall_prev) begin
      assert (m_data == m_data_prev)
      else $fatal(1, "FIFO backpressure: m_data changed during ongoing stall");
      end

      // Update history for next cycle
      m_data_prev <= m_data;
      stall_prev  <= (m_valid && !m_ready);
      
      
      // 4) Level Bounds
      assert (!(empty && (level!=0)))
      else $fatal(1, "FIFO level negative");
      
      assert (!(full && (level!=DEPTH)))
      else $fatal(1, "FIFO exceeded DEPTH");
      
    end
    
  end
   
  
  
  //Logic for the PIPE_OUT       
  always @(posedge clk) begin
    
    //Reset the pipe logic values
    if (!rst_n) begin
      pipe_valid <= 1'b0;
      pipe_data <= '0;
    
    //If the PIPE_OUT is activated
    end else if (PIPE_OUT) begin
      
      //Validifying whether we can load the next value
      if (!pipe_valid || core_ready) begin
        
        //Checks if we have another value lined up if we don't have another lined up we can't load it
        if (level_next > 0) begin
          pipe_valid <= 1'b1;
          
          //Making sure we can handle edge cases and load the right way
          if (push && ( (level == 0) || (pop && (level == 1)) )) begin
  			pipe_data <= s_data;
            
          //The normal way of loading a word
		  end else begin
  			pipe_data <= mem[rd_ptr_next]; // normal case: read from memory
		  end
          
        //If there was no next word so we tell the pipe there is no word to load
        end else begin
        	pipe_valid <= 1'b0;
        end 
      end
    end
  end
      
  
    //Logic for SKID
    always_ff @(posedge clk) begin
    if (!rst_n) begin
      skid_valid <= 1'b0;
      skid_data  <= '0;
    end else if (SKID_EN) begin
      // If skid is holding a word and sink accepts then clear skid
      if (skid_valid && m_ready) begin
        skid_valid <= 1'b0;
      end

      // If skid is empty, core has a word, and sink is not ready then capture into skid
      if (!skid_valid && core_valid && !m_ready) begin
        skid_valid <= 1'b1;
        skid_data  <= core_data;
      end
    end else begin
      // If SKID disabled keep reg 0
      skid_valid <= 1'b0;
      skid_data  <= '0;
    end
  end
        
  
  //level status
  assign empty = (level==0);
  assign full = (level==$unsigned(DEPTH));
  assign credits = $unsigned(DEPTH) - level;

  
  //Updated FIFO stauts
  //We can pop either if it's not full or if we are going to pop this cycle
  assign s_ready = !full || pop;
  
  
  //Need to define which path the data goes through:
  //If PIPE_OUT is on it goes through the pipe and if not then through the original system
  assign core_valid = (PIPE_OUT ? pipe_valid: !empty);
  assign core_data = (PIPE_OUT ? pipe_data : mem[rd_ptr]);
  
  //Defing whether or not the FIFO can pass the data onwards based on skid status 
  assign m_valid = (SKID_EN ? (skid_valid ? 1'b1 : core_valid) : core_valid);
  //Change the logic of m_data to be dependant on if skid is turned on and if there is a value in the skid
  assign m_data = (SKID_EN ? (skid_valid ? skid_data : core_data) : core_data);
  
  assign core_ready = (!SKID_EN) ? m_ready : (!skid_valid);
  
  //When push and pop activated
  assign push = s_valid && s_ready;
  //Changing pop logic to be dependant on core 
  assign pop = core_valid && core_ready;
  

  //Predicts occupancy of next edge used for PIPE_OUT
  assign level_next = $signed({1'b0, level}) + (push ? 1 : 0) - (pop  ? 1 : 0);
  assign rd_ptr_next = (pop) ? ((rd_ptr == PTR_W'(DEPTH-1)) ? '0 : (rd_ptr + 1'b1)) : rd_ptr;

   
endmodule
