function [retval, s, errorb, tau] = allan_overlap(data,tau,name,verbose)
% ALLAN_OVERLAP  Compute the overlapping Allan deviation for a set of
%   time-domain frequency data
% [RETVAL, S, ERRORB, TAU] = ALLAN_OVERLAP(DATA,TAU,NAME,VERBOSE)
%
% Inputs:
% DATA should be a struct and have the following fields:
%  DATA.freq or DATA.phase
%               A vector of fractional frequency measurements (df/f) in
%               DATA.freq *or* phase offset data (seconds) in DATA.phase
%               If phase data is not present, it will be generated by
%                integrating the fractional frequency data.
%               If both fields are present, then DATA.phase will be used.
%
%  DATA.rate or DATA.time
%               The sampling rate in Hertz (DATA.rate) or a vector of
%                timestamps for each measurement in seconds (DATA.time).
%               DATA.rate is used if both fields are present.
%               If DATA.rate == 0, then the timestamps are used.
%
% TAU is an array of tau values for computing Allan deviation.
%     TAU values must be divisible by 1/DATA.rate (data points cannot be
%     grouped in fractional quantities!). Invalid values are ignored.
% NAME is an optional label that is added to the plot titles.
% VERBOSE sets the level of status messages:
%     0 = silent & no data plots; 1 = status messages; 2 = all messages 
%
% Outputs:
% RETVAL is the array of overlapping Allan deviation values at each TAU.
% S is an optional output of other statistical measures of the data (mean, std, etc).
% ERRORB is an optional output containing the error estimates for a 1-sigma
%   confidence interval. Error bars are plotted as vertical lines at each point.
% TAU is an optional output containing the array of tau values used in the
%   calculation (which may be a truncated subset of the input or default values).
%
% Example:
%
% To compute the overlapping Allan deviation for the data in the variable "lt":
% >> lt
% lt = 
%     freq: [1x86400 double]
%     rate: 0.5
%
% Use:
%
% >> ado = allan_overlap(lt,[2 10 100],'lt data',1);
%
% The Allan deviation will be computed and plotted at tau = 2,10,100 seconds.
%  1-sigma confidence intervals will be indicated by vertical lines.
% You can also use the default settings, which are usually a good starting point:
%
% >> ado = allan_overlap(lt);
%
%
% Notes:
%  This function calculates the overlapping Allan deviation (ADEV), *not* the
%   standard ADEV. Use "allan.m" for standard ADEV.
%  The calculation is performed using phase data. If only frequency data is
%   provided, phase data is generated by integrating the frequency data.
%   However, the timestamp-based calculation is performed using frequency
%   data. Phase data is differentiated to generate frequency data if necessary.
%  No pre-processing of the data is performed, except to remove any
%   initial offset in the time record. 
%  For rate-based data, ADEV is computed only for tau values greater than the
%   minimum time between samples and less than the half the total time. For
%   time-stamped data, only tau values greater than the maximum gap between
%   samples and less than half the total time are used.
%  The calculation for fixed sample rate data is *much* faster than for
%   time-stamp data. You may wish to run the rate-based calculation first,
%   then compare with time-stamp-based. Often the differences are insignificant.
%  The error bars at each point are calculated using the 1-sigma intervals
%   based on the size of the data set. This is usually an overestimate for
%   overlapping ADEV; a more accurate (and usually smaller uncertainty)
%   value can be determined from chi-squared statistics, but that is not
%   implemented in this version.
%  You can choose between loglog and semilog plotting of results by
%   commenting in/out the appropriate line. Search for "#PLOTLOG".
%  This function has been validated using the test data from NBS Monograph
%   140, the 1000-point test data set given by Riley [1], and the example data
%   given in IEEE standard 1139-1999, Annex C.
%   The author welcomes other validation results, see contact info below.
%
% For more information, see:
% [1] W. J. Riley, "Addendum to a test suite for the calculation of time domain
%  frequency stability," presented at IEEE Frequency Control Symposium,
%  1996.
% Available on the web:
%  http://www.ieee-uffc.org/frequency_control/teaching.asp?name=paper1ht
%
%
% M.A. Hopcroft
%      mhopeng at gmail dot com
%
% I welcome your comments and feedback!
%
% *************************************************************************
% This file has been modified for NaveGo toolbox.
% *************************************************************************
% Version: 002
% Date:    2019/09/30
% Author:  Rodrigo Gonzalez <rodralez@frm.utn.edu.ar>
% URL:     https://github.com/rodralez/navego
% *************************************************************************
%
% MH Mar2014
% v2.24 fix bug related to generating freq data from phase with timestamps
%       (thanks to S. David-Grignot for finding the bug)
% MH Oct2010
% v2.22 tau truncation to integer groups; tau sort
%       plotting bugfix
% v2.20 update to match allan.m (dsplot.m, columns)
%       discard tau values with timestamp irregularities
%
% MH MAR2010
% v2.1  bugfixes for irregular sample rates
%        (thanks to Ryad Ben-El-Kezadri for feedback and testing)
%       handle empty rate field
%       fix integer comparisons for fractional sample rates
%       update consistency check
%
% MH FEB2010
% v2.0  use phase data for calculation- much faster
%       Consistent code behaviour for all "allan_x.m" functions:
%       accept phase data
%       verbose levels
%
% MH JAN2010
% v1.0  based on allan v1.84
%

%#ok<*AGROW>

versionstr = 'allan_overlap v2.24';

% defaults
if nargin < 4, verbose = 2; end
if nargin < 3, name=''; end
if nargin < 2 || isempty(tau), tau=2.^(-10:10); end
if isfield(data,'rate') && isempty(data.rate), data.rate=0; end % v2.1 

% Formatting for plots
FontName = 'Arial';
FontSize = 14;
plotlinewidth=2;

% if verbose >= 1, fprintf(1,'allan_overlap: %s\n\n',versionstr); end

%% Data consistency checks v2.1
if ~(isfield(data,'phase') || isfield(data,'freq'))
    error('Either ''phase'' or ''freq'' must be present in DATA. See help file for details. [con0]');
end
if isfield(data,'time')
    if isfield(data,'phase') && (length(data.phase) ~= length(data.time))
        if isfield(data,'freq') && (length(data.freq) ~= length(data.time))
            error('The time and freq vectors are not the same length. See help for details. [con2]');
        else
            error('The time and phase vectors are not the same length. See help for details. [con1]');
        end
    end
    if isfield(data,'phase') && (any(isnan(data.phase)) || any(isinf(data.phase)))
        error('The phase vector contains invalid elements (NaN/Inf). [con3]');
    end
    if isfield(data,'freq') && (any(isnan(data.freq)) || any(isinf(data.freq)))
        error('The freq vector contains invalid elements (NaN/Inf). [con4]');
    end
    if isfield(data,'time') && (any(isnan(data.time)) || any(isinf(data.time)))
        error('The time vector contains invalid elements (NaN/Inf). [con5]');
    end
end

% sort tau vector
tau=sort(tau);

%% Basic statistical tests on the data set
if ~isfield(data,'freq')
    if isfield(data,'rate') && data.rate ~= 0
        data.freq=diff(data.phase).*data.rate;
    elseif isfield(data,'time')
        data.freq=diff(data.phase)./diff(data.time);
    end
    if verbose >= 1, fprintf(1,'allan_overlap: Fractional frequency data generated from phase data (M=%g).\n',length(data.freq)); end
end
if size(data.freq,2) > size(data.freq,1), data.freq=data.freq'; end % ensure columns
    
s.numpoints=length(data.freq);
s.max=max(data.freq);
s.min=min(data.freq);
s.mean=mean(data.freq);
s.median=median(data.freq);
if isfield(data,'time')
    if size(data.time,2) > size(data.time,1), data.time=data.time'; end % ensure columns
    s.linear=polyfit(data.time(1:length(data.freq)),data.freq,1);
elseif isfield(data,'rate') && data.rate ~= 0
    s.linear=polyfit((1/data.rate:1/data.rate:length(data.freq)/data.rate)',data.freq,1);
else
    error('Either "time" or "rate" must be present in DATA. Type "help allan_overlap" for details. [err1]');
end
s.std=std(data.freq);

if verbose >= 2
    fprintf(1,'allan_overlap: fractional frequency data statistics:\n');
    disp(s);
end


% scale to median for plotting
medianfreq=data.freq-s.median;
sm=[]; sme=[];

% Screen for outliers using 5x Median Absolute Deviation (MAD) criteria
MAD = median(abs(medianfreq)/0.6745);
if verbose >= 1 && any(abs(medianfreq) > 5*MAD)
    
    odl = (abs(medianfreq) > 5*MAD);
    outliers = data.freq(odl);
    fprintf(1, 'allan_overlap: OUTLIERS: There appear to be %d outliers in the frequency data.\n', length(outliers));       
  
    % ELIMINATE OUTLIERS FROM DATA
    fit_line = polyval(s.linear, (1/data.rate:1/data.rate:length(data.freq)/data.rate)') - s.median;    
    idl = ( medianfreq < (5*MAD + fit_line) );
    data.freq = data.freq(idl);
    medianfreq = medianfreq(idl);
 
    fit_line = polyval(s.linear, (1/data.rate:1/data.rate:length(data.freq)/data.rate)') - s.median;
    idl = ( medianfreq > (-5*MAD + fit_line) );
    data.freq = data.freq(idl);
    medianfreq = medianfreq(idl);
    
    s.outliers = length(outliers);
    
else 
    s.outliers = 0;
end

%%%%
% There are four cases, freq or phase data, using timestamps or rate:

%% Fixed Sample Rate Data
%   If there is a regular interval between measurements, calculation is much
%   easier/faster
if isfield(data,'rate') && data.rate > 0 % if data rate was given
    if verbose >= 1
        fprintf(1, 'allan_overlap: regular data ');
        if isfield(data,'freq')
            fprintf(1, '(%g freq data points @ %g Hz)\n',length(data.freq),data.rate);
        elseif isfield(data,'phase')
            fprintf(1, '(%g phase data points @ %g Hz)\n',length(data.phase),data.rate);
        else
            error('\n phase or freq data missing [err10]');
        end
    end
  
    % string for plot title
    name=[name ' (' num2str(data.rate) ' Hz)'];

    % what is the time interval between data points?
    tmstep = 1/data.rate;      
    
    % Is there time data? Just for curiosity/plotting, does not impact calculation
    if isfield(data,'time')
        % adjust time data to remove any starting gap; first time step
        %  should not be zero for comparison with freq data
        dtime=data.time-data.time(1) + mean(diff(data.time)); 
        dtime=dtime(1:length(medianfreq)); % equalize the data vector lengths for plotting (v2.1)
        if verbose >= 2
            fprintf(1,'allan_overlap: End of timestamp data: %g sec.\n',dtime(end));
            if (data.rate - 1/mean(diff(dtime))) > 1e-6
                fprintf(1,'allan_overlap: NOTE: data.rate (%f Hz) does not match average timestamped sample rate (%f Hz)\n',data.rate,1/mean(diff(dtime)));
            end
        end
    else
        % create time axis data using rate (for plotting only)
        dtime=(tmstep:tmstep:length(data.freq)*tmstep);
    end

  
    % is phase data present? If not, generate it
    if ~isfield(data,'phase')
        nfreq=data.freq-s.mean;
        dphase=zeros(1,length(nfreq)+1);
        % -----------------------------------------------------------------
        dphase(2:end) = cumsum(nfreq)./data.rate; % INTEGRAL
        % -----------------------------------------------------------------
        if verbose >= 1, fprintf(1,'allan_overlap: phase data generated from fractional frequency data (N=%g).\n',length(dphase)); end
    else
        dphase=data.phase;
    end
    
    % check the range of tau values and truncate if necessary
    % find halfway point of time record
    halftime = round(tmstep*length(data.freq)/2);
    % truncate tau to appropriate values
    tau = tau(tau >= tmstep & tau <= halftime);
    if verbose >= 2, fprintf(1, 'allan_overlap: allowable tau range: %g to %g sec. (1/rate to total_time/2)\n',tmstep,halftime); end
    
    % number of samples
    N=length(dphase);
    % number of samples per tau period
    m = data.rate.*tau;
    % only integer values allowed for m (no fractional groups of points)
    %tau = tau(m-round(m)<1e-8); % numerical precision issues (v2.1)
    tau = tau(m==round(m));  % The round() test is only correct for values < 2^53
    %m = m(m-round(m)<1e-8); % change to round(m) for integer test v2.22
    m = m(m==round(m));
    %m=round(m);
    %fprintf(1,'m: %.50f\n',m)
        
    if verbose >= 1, fprintf(1,'allan_overlap: calculating overlapping Allan deviation...\n       '); end
    
    % calculate the Allan deviation for each value of tau
    k=0; tic;
    for i = tau
        k=k+1;
        if verbose >= 2, fprintf(1,'%d ',i); end


        % pad phase data set length to an even multiple of this tau value
        mphase=zeros(ceil(length(dphase)./m(k))*m(k),1);
        mphase(1:N)=dphase;
        % group phase values
        mp=reshape(mphase,m(k),[]);
        % compute second differences of phase values (x_k+m - x_k)
        md1=diff(mp,1,2);
        md2=diff(md1,1,2);
        md1=reshape(md2,1,[]);
        
        % compute overlapping ADEV from phase values
        %  only the first N-2*m(k) samples are valid
        sm(k)=sqrt((1/(2*(N-2*m(k))*i^2))*sum(md1(1:N-2*m(k)).^2));
        
        % estimate error bars
        sme(k)=sm(k)/sqrt(N-2*m(k));
        

    end % repeat for each value of tau
    
    if verbose >= 2, fprintf(1,'\n'); end
    calctime=toc; if verbose >= 2, fprintf(1,'allan_overlap: Elapsed time for calculation: %g seconds\n',calctime); end

        
    
%% Irregular data, no fixed interval    
elseif isfield(data,'time')
    % the interval between measurements is irregular
    %  so we must group the data by time
    if verbose >= 1, fprintf(1, 'allan_overlap: irregular rate data (no fixed sample rate)\n'); end

    
    % string for plot title
    name=[name ' (timestamp)'];
    

    % adjust time to remove any starting offset
    dtime=data.time-data.time(1)+mean(diff(data.time));
    
    % save the freq data for the loop
    dfreq=data.freq;
    dtime=dtime(1:length(dfreq));
    
    dfdtime=diff(dtime); % only need to do this once (v2.1)
    % where is the maximum gap in time record?
    gap_pos=find(dfdtime==max(dfdtime));
    % what is average data spacing?
    avg_gap = mean(dfdtime);
    s.avg_rate = 1/avg_gap; % save avg rate for user (v2.1)
    
    if verbose >= 2
        fprintf(1, 'allan_overlap: WARNING: irregular timestamp data (no fixed sample rate).\n');
        fprintf(1, '       Calculation time may be long and the results subject to interpretation.\n');
        fprintf(1, '       You are advised to estimate using an average sample rate (%g Hz) instead of timestamps.\n',1/avg_gap);
        fprintf(1, '       Continue at your own risk! (press any key to continue)\n');
        pause;
    end
    
    if verbose >= 1
        fprintf(1, 'allan_overlap: End of timestamp data: %g sec\n',dtime(end));
    	fprintf(1, '       Average rate: %g Hz (%g sec/measurement)\n',1/avg_gap,avg_gap);
        if max(diff(dtime)) ~= 1/mean(diff(dtime))
            fprintf(1, '       Max. gap in time record: %g sec at position %d\n',max(dfdtime),gap_pos(1));
        end
        if max(diff(dtime)) > 5*avg_gap
            fprintf(1, '       WARNING: Max. gap in time record is suspiciously large (>5x the average interval).\n');
        end
    end
    

    % find halfway point
    halftime = fix(dtime(end)/2);
    % truncate tau to appropriate values
    tau = tau(tau >= max(dfdtime) & tau <= halftime);
    if isempty(tau)
        error('allan_overlap: ERROR: no appropriate tau values (> %g s, < %g s)\n',max(dfdtime),halftime);
    end
    

    % number of samples
    M=length(dfreq);
    % number of samples per tau period
    m=round(tau./avg_gap);

    if verbose >= 1, fprintf(1,'allan_overlap: calculating overlapping Allan deviation...\n'); end

    k=0; tic;
    for i = tau
        k=k+1;
        fa=[];

%         if verbose >= 2, fprintf(1,'%d ',i); end
        
        freq = dfreq; time = dtime;
               
        % compute overlapping samples (y_k) for this tau
        %for j = 1:i
        for j = 1:m(k) % (v2.1)
            km=0;
            %fprintf(1,'j: %d ',j);

            % (v2.1) truncating not correct for overlapping samples
            % truncate data set to an even multiple of this tau value
            %freq = freq(time <= time(end)-rem(time(end),i));
            %time = time(time <= time(end)-rem(time(end),i));
                        
            % break up the data into overlapping groups of tau length
            while i*km <= time(end)
                km=km+1;
                %i*km

                % progress bar
                if verbose >= 2
                    if rem(km,100)==0, fprintf(1,'.'); end
                    if rem(km,1000)==0, fprintf(1,'%g/%g\n',km,round(time(end)/i)); end
                end

                f = freq(i*(km-1) < (time) & (time) <= i*km);

                if ~isempty(f)
                    fa(j,km)=mean(f);
                else
                    fa(j,km)=0;
                end

            end
            %fa
            
            % shift data vector by -1 and repeat
            freq=circshift(dfreq,(size(freq)>1)*-j);
            freq(end-j+1:end)=[];
            time=circshift(dtime,(size(time)>1)*-j);
            time(end-j+1:end)=[];
            time=time-time(1)+avg_gap; % remove time offset
            
        end
        
        % compute second differences of fractional frequency values (y_k+m - y_k)
        fd1=diff(fa,1,2);
        fd1=reshape(fd1,1,[]);
        % compute overlapping ADEV from fractional frequency values
        %  only the first M-2*m(k)+1 samples are valid
        if length(fd1) >= M-2*m(k)+1
            sm(k)=sqrt((1/(2*(M-2*m(k)+1)))*sum(fd1(1:M-2*m(k)+1).^2));

            % estimate error bars
            sme(k)=sm(k)/sqrt(M+1);
            
            if verbose >= 2, fprintf(1,'\n'); end
            
        else
            if verbose >=2, fprintf(1,' tau=%g dropped due to timestamp irregularities\n',tau(k)); end
            sm(k)=0; sme(k)=0;
        end
        

    end

    if verbose >= 2, fprintf(1,'\n'); end
    calctime=toc; if verbose >= 1, fprintf(1,'allan_overlap: Elapsed time for calculation: %g seconds\n',calctime); end

    % remove any points that were dropped
    tau(sm==0)=[];
    sm(sm==0)=[];
    sme(sme==0)=[];



else
    error('allan_overlap: WARNING: no DATA.rate or DATA.time! Type "help allan" for more information. [err2]');
end


%%%%%%%%
%% Plotting

if verbose >= 1 % show all data
    
    % plot the frequency data, centered on median
    if size(dtime,2) > size(dtime,1), dtime=dtime'; end % this should not be necessary, but dsplot 1.1 is a little bit brittle
    try
        % dsplot makes a new figure
        hd=dsplot(dtime,medianfreq);
    catch ME
        figure;
        hd=plot(dtime,medianfreq);
        if verbose >= 1, fprintf(1,'allan_overlap: Note: Install dsplot.m for improved plotting of large data sets (File Exchange File ID: #15850).\n'); end
        if verbose >= 2, fprintf(1,'             (Message: %s)\n',ME.message); end
    end
    set(hd,'Marker','.','LineStyle','none','Color','b'); % equivalent to '.-'
    hold on;

    fx = xlim;
%     plot([fx(1) fx(2)],[s.median s.median],'-k');
    plot([fx(1) fx(2)],[0 0],':k');
    
    % show 5x Median Absolute deviation (MAD) values
    hm=plot([fx(1) fx(2)],[5*MAD 5*MAD],'-r');
    plot([fx(1) fx(2)],[-5*MAD -5*MAD],'-r');
    
    % show linear fit line
    hf=plot(xlim,polyval(s.linear,xlim)-s.median,'-g');    
    title(['Data: ' name],'FontSize',FontSize+2,'FontName','Arial');
    
    plot(xlim,polyval(s.linear,xlim)-s.median-3*MAD,'--m'); 
    plot(xlim,polyval(s.linear,xlim)-s.median+3*MAD,'--m');
    
    %set(get(gca,'Title'),'Interpreter','none');
    xlabel('Time [sec]','FontSize',FontSize,'FontName',FontName);
    if isfield(data,'units')
        ylabel(['data - median(data) [' data.units ']'],'FontSize',FontSize,'FontName',FontName);
    else
        ylabel('freq - median(freq)','FontSize',FontSize,'FontName',FontName);
    end
    set(gca,'FontSize',FontSize,'FontName',FontName);
    legend([hd hm hf],{'data (centered on median)','5x MAD outliers',['Linear Fit (' num2str(s.linear(1),'%g') ')']},'FontSize',max(10,FontSize-2));
    % tighten up
    xlim([dtime(1) dtime(end)]);
    
end % end plot raw data


if verbose >= 2 % show analysis results

    % plot Allan deviation results
    if ~isempty(sm)
%         figure
% 
%         % Choose loglog or semilogx plot here    #PLOTLOG
%         %semilogx(tau,sm,'.-b','LineWidth',plotlinewidth,'MarkerSize',24);
%         loglog(tau,sm,'.-b','LineWidth',plotlinewidth,'MarkerSize',24);
% 
%         % in R14SP3, there is a bug that screws up the error bars on a semilog plot.
%         %  When this is fixed, uncomment below to use normal errorbars
%         errorbar(tau,sm,sme,'.-b'); set(gca,'XScale','log');
%         % this is a hack to approximate the error bars
% %         hold on; plot([tau; tau],[sm+sme; sm-sme],'-k','LineWidth',max(plotlinewidth-1,2));
% 
%         grid on;
%         title(['Overlapping Allan Deviation: ' name],'FontSize',FontSize+2,'FontName',FontName);
%         %set(get(gca,'Title'),'Interpreter','none');
%         xlabel('\tau [sec]','FontSize',FontSize,'FontName','Arial');
%         ylabel(' Overlapping \sigma_y(\tau)','FontSize',FontSize,'FontName',FontName);
%         set(gca,'FontSize',FontSize,'FontName',FontName);
%         % expand the x axis a little bit so that the errors bars look nice
%         adax = axis;
%         axis([adax(1)*0.9 adax(2)*1.1 adax(3) adax(4)]);
        
        % display the minimum value
        fprintf(1,'allan: Minimum overlapping ADEV value: %g at tau = %g seconds\n',min(sm),tau(sm==min(sm)));        
        
    elseif verbose >= 1
        fprintf(1,'allan_overlap: WARNING: no values calculated.\n');
        fprintf(1,'       Check that TAU > 1/DATA.rate and TAU values are divisible by 1/DATA.rate\n');
        fprintf(1,'Type "help allan_overlap" for more information.\n\n');
    end
    
end % end plot analysis
        
retval = sm;
errorb = sme;

return
