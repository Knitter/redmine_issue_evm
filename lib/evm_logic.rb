module EvmLogic

  class IssueEvm

    def initialize baselines, issues, costs, basis_date, forecast, etc_method, calc_basis_actual, performance
      @basis_date = basis_date
      #option
      @forecast = forecast
      @etc_method = etc_method
      @performance = performance
      @issue_max_date = issues.maximum(:due_date)
      #PV-ACTUAL for chart
      @pv_actual = calculate_planed_value issues
      #PV-BASELINE for chart
      @pv_baseline = calculate_planed_value baselines
      #PV 
      @pv = calc_basis_actual ? @pv_actual : @pv_baseline
      #EV
      @ev = calculate_earned_value issues
      #AC
      @ac = calculate_actual_cost costs
      # Project finished?
      if @pv[@pv.keys.max] == @ev[@ev.keys.max]
        @project_is_fibished = true
        delete_basis_date = [@pv.keys.max, @ev.keys.max, @ac.keys.max].max
        @pv.delete_if{|date, value| date > delete_basis_date }
        @ev.delete_if{|date, value| date > delete_basis_date }
        @ac.delete_if{|date, value| date > delete_basis_date }
      end
      #To calculate the EVM value
      @pv_value = @pv[basis_date].nil? ? @pv[@pv.keys.max] : @pv[basis_date]
      @ev_value = @ev[basis_date].nil? ? @ev[@ev.keys.max] : @ev[basis_date]
      @ac_value = @ac[basis_date].nil? ? @ac[@ac.keys.max] : @ac[basis_date]
    end


    #Basis date
    def basis_date
      @basis_date
    end


    #BAC
    def bac hours
      bac = @pv[@pv.keys.max] / hours
      bac.round(2)
    end


    #CompleteEV
    def complete_ev hours
      complete_ev = bac(hours) == 0.0 ? 0.0 : (today_ev(hours) / bac(hours)) * 100.0
      complete_ev.round(2)
    end
    

    #PV
    def today_pv hours
      pv = @pv_value / hours
      pv.round(2)
    end


    #EV
    def today_ev hours
      ev = @ev_value / hours
      ev.round(2)
    end
    

    #AC
    def today_ac hours
      ac = @ac_value / hours
      ac.round(2)
    end


    #SV
    def today_sv hours
      sv = today_ev(hours) - today_pv(hours)
      sv.round(2)
    end


    #CV
    def today_cv hours
      cv = today_ev(hours) - today_ac(hours)
      cv.round(2)
    end


    #SPI
    def today_spi hours
      spi = today_ev(hours) == 0.0 || today_pv(hours) == 0.0 ? 0.0 : today_ev(hours) / today_pv(hours)
      spi.round(2)
    end


    #CPI
    def today_cpi hours
      cpi = today_ev(hours) == 0.0 || today_ac(hours) == 0.0 ? 0.0 : today_ev(hours) / today_ac(hours)
      cpi.round(2)
    end


    #CR
    def today_cr hours
      cr = today_spi(hours) * today_cpi(hours)
      cr.round(2)
    end


    #ETC
    def etc hours
      if today_cpi(hours) == 0.0 || today_cr(hours) == 0.0
        etc = 0.0  
      else
        case @etc_method
        when 'method1' then
          div_value = 1.0
        when 'method2' then
          div_value = today_cpi(hours)
        when 'method3' then
          div_value = today_cr(hours)
        else
          div_value = today_cpi(hours)
        end
        etc = (bac(hours) - today_ev(hours)) / div_value
      end
      etc.round(2)
    end
    

    #EAC
    def eac hours
      eac = today_ac(hours) + etc(hours)
      eac.round(2)
    end


    #VAC
    def vac hours
      vac = bac(hours) - eac(hours)
      vac.round(2)
    end

    #Delay
    def delay
      (forecast_finish_date - @pv.keys.max).to_i
    end


    #TCPI = (BAC - EV) / (BAC - AC)
    def tcpi hours
      tcpi = bac(hours) == 0.0 ? 0.0 : (bac(hours) - today_ev(hours)) / (bac(hours) - today_ac(hours))
      tcpi.round(2)
    end
    

    #Create chart data
    def chart_data
      if @issue_max_date < @basis_date && complete_ev(8) < 100.0
        @ev[@basis_date] = @ev[@ev.keys.max]
        @ac[@basis_date] = @ac[@ac.keys.max]
      end
      chart_date = {}
      chart_date['planned_value'] = convert_to_chart(@pv_actual)
      chart_date['actual_cost'] = convert_to_chart(@ac)
      chart_date['earned_value'] = convert_to_chart(@ev)
      chart_date['baseline_value'] = convert_to_chart(@pv_baseline)
      if @forecast
        bac_top_line = {chart_minimum_date => bac(1), chart_maximum_date => bac(1)}
        chart_date['bac_top_line'] = convert_to_chart(bac_top_line)
        eac_top_line = {chart_minimum_date => eac(1), chart_maximum_date => eac(1)}
        chart_date['eac_top_line'] = convert_to_chart(eac_top_line)
        if @project_is_fibished
          actual_cost_forecast = {forecast_finish_date => eac(1)}
        else
          actual_cost_forecast = {@basis_date => today_ac(1), forecast_finish_date => eac(1)}
        end
        chart_date['actual_cost_forecast'] = convert_to_chart(actual_cost_forecast)
        if @project_is_fibished
          earned_value_forecast = {forecast_finish_date => @pv[@pv.keys.max]}
        else
          earned_value_forecast = {@basis_date => today_ev(1), forecast_finish_date => @pv[@pv.keys.max]}
        end
        chart_date['earned_value_forecast'] = convert_to_chart(earned_value_forecast)
      end
      if @performance
        create_performance_index_hash
        chart_date['spi'] = convert_to_chart(@spi)
        chart_date['cpi'] = convert_to_chart(@cpi)
        chart_date['cr'] = convert_to_chart(@cr)
      end 
      chart_date
    end


    def create_performance_index_hash
      @spi = {}
      @cpi = {}
      @cr = {}
      new_ev = complement_evm_value @ev
      new_ac = complement_evm_value @ac
      new_pv = complement_evm_value @pv
      performance_min_date = [new_ev.keys.min, new_ev.keys.min, new_ev.keys.min].max
      performance_max_date = [new_ev.keys.max, new_ev.keys.max, new_ev.keys.max].min
      (performance_min_date..performance_max_date).each do |date|
        @spi[date] = (new_ev[date] / new_pv[date]).round(2)
        @cpi[date] = (new_ev[date] / new_ac[date]).round(2) 
        @cr[date] = (@spi[date] * @cpi[date]).round(2)
      end
    end


    private


      def calculate_planed_value issues
        temp_pv = {}
        unless issues.nil?
          issues.each do |issue|
            next unless issue.leaf?
            hours_per_day = issue_hours_per_day(issue.estimated_hours, issue.start_date, issue.due_date)
            (issue.start_date..issue.due_date).each do |date|
              temp_pv[date].nil? ? temp_pv[date] = hours_per_day : temp_pv[date] += hours_per_day
            end
          end
        end
        calculate_planed_value = sort_and_sum_evm_hash(temp_pv)
      end


      def calculate_earned_value issues
        temp_ev = {}
        unless issues.nil?
          issues.each do |issue|
            next unless issue.leaf?
            if issue.closed?
              close_date = issue.closed_on.utc.to_date
              temp_ev[close_date].nil? ? temp_ev[close_date] = issue.estimated_hours : temp_ev[close_date] += issue.estimated_hours
            elsif issue.done_ratio > 0
              estimated_hours = issue.estimated_hours * issue.done_ratio / 100.0
              start_date = [issue.start_date, @basis_date].min
              end_date = [issue.due_date, @basis_date].max
              hours_per_day = issue_hours_per_day(estimated_hours, start_date, end_date)
              (start_date..end_date).each do |date|
                temp_ev[date].nil? ? temp_ev[date] = hours_per_day : temp_ev[date] += hours_per_day
              end 
            end
          end
        end
        calculate_earned_value = sort_and_sum_evm_hash(temp_ev)
        calculate_earned_value.delete_if{|date, value| date > @basis_date }
      end


      def calculate_actual_cost costs
        temp_ac = {}
        temp_ac = Hash[costs]
        calculate_actual_cost = sort_and_sum_evm_hash(temp_ac)
      end


      def convert_to_chart hash_with_data 
        hash_converted = Hash[hash_with_data.map{ |k, v| [k.to_time(:utc).to_i * 1000, v] }]
        hash_converted.to_a
      end


      def sort_and_sum_evm_hash evm_hash 
        temp_hash = {}
        sum_value = 0.0
        if evm_hash.blank?
          evm_hash[@basis_date] = 0.0
        elsif @basis_date <= @issue_max_date 
          evm_hash[@basis_date] = 0.0 if evm_hash[@basis_date].nil?
        end
        evm_hash.sort_by{|key,val| key}.each do |date , value|
          sum_value += value
          temp_hash[date] = sum_value
        end        
        temp_hash
      end
    

      def issue_hours_per_day estimated_hours, start_date, end_date
        estimated_hours / (end_date - start_date + 1)
      end


      def chart_minimum_date
        [@pv.keys.min, @ev.keys.min, @ac.keys.min].min
      end


      def chart_maximum_date
        [@pv.keys.max, @ev.keys.max, @ac.keys.max, forecast_finish_date].max
      end


      def forecast_finish_date
        if complete_ev(8) == 100.00
          finish_date = @ev.keys.max
        elsif today_spi(8) == 0.0
          finish_date = @pv.keys.max
        else
          if @issue_max_date < @basis_date
            rest_days = (@pv[@pv.keys.max] - @ev[@ev.keys.max]) / 8 / today_spi(8)
            finish_date = @basis_date + rest_days
          else
            rest_days =  @pv.reject{|key, value| key <= @basis_date }.size
            finish_date = @pv.keys.max - (rest_days - (rest_days / today_spi(8)) )
          end
        end
      end


      def complement_evm_value evm_hash
        before_date = evm_hash.keys.min
        before_value = evm_hash[evm_hash.keys.min]
        temp = {}
        evm_hash.each do |date , value|
          dif_days = ( date - before_date -1 ).to_i
          dif_value = ( value - before_value ) / dif_days
          if dif_days > 0
            sum_value = 0.0
            for add_days in 1..dif_days do
              tmpdate = before_date + add_days
              sum_value += dif_value
              temp[tmpdate] = before_value + sum_value
            end
          end
          before_date = date
          before_value = value
          temp[date] = value
        end
        temp
      end

  end

end
