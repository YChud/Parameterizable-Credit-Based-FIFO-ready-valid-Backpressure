//I built the TB with the assumption that all tests can be run back to back to I put reset in between certain tests that need to be reset before

module testbench;
  logic clk = 0;
  logic rst_n;

  logic s_valid;
  logic s_ready;
  logic [31:0] s_data;

  logic m_valid;
  logic m_ready;
  logic [31:0] m_data;

  logic [$clog2(8+1)-1:0] level;
  logic empty, full;
  logic [$clog2(8+1)-1:0] credits;

  logic [31:0] popped_word; 
  logic [31:0] pushed_word;
  
  logic [31:0] exp_q[$];
  logic [31:0] exp;
  
  logic push_evt, pop_evt;
  logic [31:0] pop_data;
  
  //Logic for Coverage
  logic pop, push;
  int hit_full, hit_empty, hit_push_pop;
  int backpressure;
  //Specifically for DEPTH=8
  int lev1, lev2, lev3, lev4, lev5, lev6, lev7;
  


  //Clock repeats every 5 units for full period of 10
  always #5 clk = ~clk;

  //Checks on clockedge if the following things happen and add to counter
  //(Specifically for DEPTH=8)
  always @(posedge clk) begin
    if (full) hit_full++;
    if (empty) hit_empty++;
    if (push && pop) hit_push_pop++;
    if (level == 1) lev1++;
    if (level == 2) lev2++;
    if (level == 3) lev3++;
    if (level == 4) lev4++;
    if (level == 5) lev5++;
    if (level == 6) lev6++;
    if (level == 7) lev7++;
    if (m_valid && !m_ready) backpressure++;
   
  end

  
  assign push = s_valid && s_ready;
  assign pop = m_valid && m_ready;
  


  
  
  fifo #(.Data_W(32), .DEPTH(8), .PIPE_OUT(0), .SKID_EN(0)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
    .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
    .level(level), .empty(empty), .full(full), .credits(credits)
  );

  //Create a task to help us keep track of the status throughout the simulations
  task automatic print_status(string tag);
    $display("[%0t] %s | s_valid=%0b s_ready=%0b | s_data=0x%08h | m_valid=%0b m_ready=%0b | m_data=0x%08h | level=%0d empty=%0b full=%0b credits=%0d",
             $time, tag, s_valid, s_ready, s_data, m_valid, m_ready, m_data, level, empty, full, credits);
  endtask

  
  initial begin
    rst_n   = 0;
    s_valid = 0;
    s_data  = '0;
    m_ready = 0;
    popped_word = '0;
    
//Test smoke reset
    // Reset for 2 cycles
    $display("RESET");
    repeat (2) @(posedge clk);
    rst_n = 1;

    @(posedge clk);
    #1;
    print_status("after reset release");
    
   
    
//Test One Push    
    $display("ONE PUSH");
    //Setting the Source to be ready to send data with a data value given
  	s_data  = 32'hA5A5_0001;
	  s_valid = 1;
    
    #1;
    print_status("Before posedge");

	  // Wait for the edge where handshake happens
	  do @(posedge clk); while (!(s_valid && s_ready));

	  #1;
	  print_status("after push handshake");
    
    //Set values back to 0 to make sure no new data gets through
	  s_valid = 1'b0;
    s_data = '0;
    
    @(posedge clk);
	
    
    
//Test One POP    
    //Now we will pop the value we pushed
    $display("ONE POP");
    //Setting the Sink to be ready to recieve values
    m_ready = 1'b1;
    
    do @(posedge clk); while (!(m_ready&&m_valid));
    
    popped_word = m_data;

	  #1;
    //Reset sink readiness to make sure no new values get pushed
    m_ready = 1'b0;
    //Status display to make sure the parameters are what they are supposed to be and seeing that the popped word is what we want
	  print_status("after POP handshake");
	  $display("POPPED_WORD = 0x%08h", popped_word);

	
    
//Test Fill    
    $display("TEST FILL");
    for (int i = 0; i < 9; i++) begin
      s_data=32'hA5A5_0000 + i;
      s_valid=1;
      
      do @(posedge clk); while (!(s_valid&&s_ready));
      
      #1;
      print_status($sformatf("after push %0d", i));
    end
    
    #1;

    //Make Sure no new data gets through
    s_valid=1'b0;
    s_data='0;
    
    

//Test empty
    $display("TEST EMPTY");
    for (int j =0; j<8; j++) begin
      //We turn the sink on
      m_ready=1'b1;
      
      do @(posedge clk); while (!(m_ready&&m_valid));
    
      popped_word = m_data;

      #1;
      //Print the status of popped words to keep track of what's coming out
      print_status("after POP handshake");
      $display("POPPED_WORD = 0x%08h", popped_word);
      
    end
    
    #15;
    //Turn off sink
    m_ready=1'b0;
    
    
    
    
//Test simultanous Push and Pop
    $display("Simultanous Push and POP");
    //Load up a bit of the FIFO
    for (int k = 0; k<6; k++) begin
      s_data=32'hA5A5_1000 + k;
      s_valid=1'b1;
      
      do @(posedge clk); while (!(s_valid&&s_ready));
      
      #1;
      print_status($sformatf("after push %0d", k));
      
    end
    
    //Set Parameters for the test
    //We make sure that both the side of the Source and the Sink are ready
    s_valid=1'b0;
    s_data=32'hA5A5_2000;
    s_valid=1'b1;
    m_ready=1'b1;
    
    //At clock edge everything updates
    @(posedge clk);
    
    popped_word=m_data;
    pushed_word=s_data;
    #1;
    //Print status to see if the results are as expected
    print_status("After simultanous pop and push");
    $display("PUSHED_WORD = 0x%08h", pushed_word);
    $display("POPPED_WORD = 0x%08h", popped_word);
    
//Reset Mode to prepare for next test
    $display("RESET FOR NEXT TEST");
    m_ready=1'b0;
    rst_n=0;
    s_data=1'b0;
    s_valid=1'b0;
    
    @(posedge clk);
    #1;
    print_status("After RESET");
    
    rst_n=1;
    #1;

  
    
//Test Random Inputs
    $display("Random Inputs");
    for (int i=0; i<1500; i++) begin
      //Each cycle it's decided randomly what the status of the Source and Sink are
      s_valid=$urandom_range(0,1);
      m_ready=$urandom_range(0,1);
      s_data=$urandom;

      //Printing status before and after clock edge to keep track of data flow
      print_status($sformatf("Before Clock Edge number %0d", i));
      
      @(posedge clk);
      #1;
      
      print_status($sformatf("At Clock Edge number %0d", i));

      //Declare assertions with scoreboard to make sure the data is flowing at the right times
      if (m_valid&&m_ready) begin
        //Assertion to make sure that only pops when there is something in the FIFO
        assert(exp_q.size()>0) else $fatal(1,"POP when scoreboard empty at i=%0d", i);
        exp=exp_q.pop_front();
        //Assertion to make sure that the data popped matches the scoreboard data
        assert(m_data==exp) else $fatal(1,"Mismatch: got %h expected %h at i=%0d", m_data, exp, i);
      end
      
      //Pushing values to the scoreboard as values get pushed to the FIFO
      if (s_valid&&s_ready) begin
        exp_q.push_back(s_data);
      end

      //Print to see data flow
      #1
      print_status($sformatf("After Clock Edge number %0d", i));
      
    end



    
//Displaying coverage to make sure the TB hit edge cases
//This is specifically for DEPTH=8
  	$display("==== FUNCTIONAL COVERAGE SUMMARY ====");
  	$display("full hits      : %0d", hit_full);
  	$display("empty hits     : %0d", hit_empty);
  	$display("push+pop hits  : %0d", hit_push_pop);
    $display("Level 1 Visits : %0d", lev1);
    $display("Level 2 Visits : %0d", lev2);
    $display("Level 3 Visits : %0d", lev3);
    $display("Level 4 Visits : %0d", lev4);
    $display("Level 5 Visits : %0d", lev5);
    $display("Level 6 Visits : %0d", lev6);
    $display("Level 7 Visits : %0d", lev7);
    $display("#Backpressure  : %0d", backpressure);
    
  end
  
    

    
      
endmodule
