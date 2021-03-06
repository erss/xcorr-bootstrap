function [ model, b ] = remove_artifacts_all_lobes( model, patient_coordinates )
% Procedure to detect and remove all artifacts. Divdes signals into 4
% regions corresponding to each brain lobe. Compute
% average spectrum of signals within each region. Fit line to log f-log
% power. If slope is > -2, mark as artifact.


% Load sampling frequency and define artifact threshold.
f0=model.sampling_frequency;
threshold = - 2;

% Load data + remove mean
data = model.data;
m = mean(data,2);
m = repmat(m,[1 size(data,2)]);
data = data - m;
model.data = data;

% Load subnetworks
[LNp,RNp] = find_subnetwork_lobe( patient_coordinates,'parietal');
[LNt,RNt] = find_subnetwork_lobe( patient_coordinates,'temporal');
[LNo,RNo] = find_subnetwork_lobe( patient_coordinates,'occipital');
[LNf,RNf] = find_subnetwork_lobe( patient_coordinates,'frontal');
if isfield(model,'t_clean')
    
    data_clean = remove_bad_channels( model );
    for t = 1:length(model.t_clean)
        
        if isnan(model.t_clean(t))
            data_clean(:,t) = nan;
        end
    end
    data_clean       = bsxfun(@minus,data_clean,nanmean(data_clean,2));
    model.data_clean = data_clean;
    b                = nan;
else
    
    % Remove bad channels before computing average slope
    data = remove_bad_channels(model);
    
    t = model.t;
    window_step = 0.5;
    window_size = 0.5;
    i_total = 1+floor((t(end)-t(1)-window_size) /window_step);  % # intervals.
    
    data_clean = data;
    t_clean    = t;
    
    b = zeros(4,i_total);
    for k = 1:i_total
        t_start = t(1) + (k-1) * window_step;   %... get window start time [s],
        t_stop  = t_start + window_size;                  %... get window stop time [s],
        indices = t >= t_start & t < t_stop;
        
        f_start = 30;
        f_stop  = 95;
        
        
        % %% Parietal
        b(1,k) = compute_slope(data([LNp;RNp],indices)',f0,f_start,f_stop);
        %%% Occip
        b(2,k) = compute_slope(data([LNo;RNo],indices)',f0,f_start,f_stop);
        %%% Temporal
        b(3,k) = compute_slope(data([LNt;RNt],indices)',f0,f_start,f_stop);
        %%%Frontal
        b(4,k) = compute_slope(data([LNf;RNf],indices)',f0,f_start,f_stop);
        
        bt = b(:,k) > threshold;
        if sum(bt(:)) > 0 % if at least one slope is greater than threshold
            % then artifact
            data_clean(:,indices) = NaN;
            t_clean(indices)      = NaN;
        end
        fprintf([num2str(k),'\n'])
        
    end
    % Remove mean after removing bad time intervalss
    model.data_clean = bsxfun(@minus,data_clean,nanmean(data_clean,2));
    model.t_clean    = t_clean;
    model.bvalues    = b;
end


end

