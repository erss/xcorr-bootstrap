function [ model ] = infer_network_imaginary_coherency( model)
% Infers network structure using coherence + imaginary coherency; 
% Employs a bootstrap procedure to determine significance.


% 1. Load model parameters
nsurrogates = model.nsurrogates;
data = model.data_clean;
time = model.t;
n = size(model.data_clean,1);  % number of electrodes
Fs = model.sampling_frequency;

% 2. Compute coherence + imaginary coherency for data.

% NOTE: We are analyzing BETA, but possible bands for interest could be:
% delta (1-4 Hz), theta (4-8 Hz), alpha (8-12 Hz), beta (12-30 Hz), 
% gamma (30-50 Hz)

f_start = 21; % Because frequency resolution = 9, f_start=f_stop = 21, and
f_stop  = 21; % 21+-9 = [12-30] gives us beta band
    
TW = model.window_size*9;                                    % Time bandwidth product.
ntapers         = 2*TW-1;                                    % Choose the # of tapers.
params.tapers   = [TW,ntapers];                              % ... time-bandwidth product and tapers.
params.pad      = -1;                                        % ... no zero padding.
params.trialave = 1;                                         % ... trial average.
params.fpass    = [1 50.1];                                  % ... freq range to pass.
params.Fs       = Fs;                                        % ... sampling frequency.
movingwin       = [ model.window_size, model.window_step];   % ... Window size and step.


%%% If imaginary coherency AND coherence already exist, skip this step.
if ~isfield(model,'kIC_beta') || ~isfield(model,'kC')
    
    d1 = data(1,:)';
    d2 = data(2,:)';
  %  [~,~,~,~,~,t,f]=cohgramc_MAK(d1,d2,movingwin,params);
   [~,~,~,~,~,t,f]=cohgramc(d1,d2,movingwin,params); 
    kIC_beta  = zeros([n n length(t)]);
    kC  = zeros([n n length(t)]);
    
    % Compute the coherence and imaginary coherency.
    % Note that coherence is positive and imaginary coherency is +/-
 %%%% MANU: subtract mean before -- this is done in the remove artifacts
 %%%% step
    for i = 1:n
        d1 = data(i,:)';
        parfor j = (i+1):n % parfor on inside,
            d2 = data(j,:)';
            [net_coh,~,S12,S1,S2,~,ftmp]=cohgramc(d1,d2,movingwin,params);
            f_indices = ftmp >= f_start & ftmp <= f_stop;
            cross_spec = mean(S12(:,f_indices),2);
            spec1      = mean(S1(:,f_indices),2);
            spec2      = mean(S2(:,f_indices),2);
            kIC_beta(i,j,:) = imag(cross_spec) ./ sqrt( spec1 ) ./ sqrt( spec2 );
            kC(i,j,:) =  mean(net_coh(:,f_indices),2);
            fprintf(['Infering edge row: ' num2str(i) ' and col: ' num2str(j) '. \n' ])
        end
        fprintf(['Inferred edge row: ' num2str(i) '\n' ])

    end
    
model.dynamic_network_taxis = t + time(1); %%% DOUBLE CHECK THIS STEP, to
                                           %%% TO FIX TIME AXIS
model.kIC_beta  = kIC_beta;
model.f = f;
model.kC = kC;
end

% % 3. Compute surrogate distrubution.
fprintf(['... generating surrogate distribution \n'])
if ~isfield(model,'distr_imag_coh') || ~isfield(model,'distr_coh')
    model = gen_surrogate_distr_coh(model,params,movingwin,f_start,f_stop);
end
% 
% % 4. Compute pvals using surrogate distribution.
fprintf(['... computing pvals \n'])

% Initialize imaginary coherency pvals
pval_imag_coh =  NaN(size(model.kIC_beta));
% distr_imag_coh = sort(abs(model.distr_imag_coh)); % MAKE DIST ALL POSTIVE

% Initialize coherence pvals
pval_coh = NaN(size(model.kIC_beta));
distr_coh = sort(model.distr_coh);

num_nets = size(pval_imag_coh,3);

for i = 1:n
    for j = (i+1):n
        
        for k = 1:num_nets
            
%             % Compute imaginary coherence for node pair (i,j) at time k
%             kBetaTemp = abs(model.kIC_beta(i,j,k)); % MAKE DIST ALL POSTIVE
%          
%             if isnan(kBetaTemp)
%                 pval_imag_coh(i,j,k)=NaN;
%             else
%                 p =sum(distr_imag_coh>kBetaTemp); % upper tail
%                 pval_imag_coh(i,j,k)= p/nsurrogates;
%                 if (p == 0)
%                     pval_imag_coh(i,j,k)=0.5/nsurrogates;
%                 end    
%             end
            
            % Compute coherence for node pair (i,j) at time k
            kCohTemp = model.kC(i,j,k);
            if isnan(kCohTemp)
                pval_coh(i,j,k)=NaN;
            else
                p =sum(distr_coh>kCohTemp); % upper tail
                pval_coh(i,j,k)= p/nsurrogates;
                if (p == 0)
                    pval_coh(i,j,k)=0.5/nsurrogates;
                end
            end
            
        end
    end
end


% 5. Use FDR to determine significant pvals.
fprintf(['... computing significance (FDR) \n'])
q=model.q;
m = (n^2-n)/2;                 % number of total tests performed
ivals = (1:m)';
sp = ivals*q/m;

% Compute significant pvals for coherence
net_coh = zeros(n,n,num_nets);

for ii = 1:num_nets
    if sum(sum(isfinite(pval_coh(:,:,ii)))) >0
        adj_mat = pval_coh(:,:,ii);
        p = adj_mat(isfinite(adj_mat));
        p = sort(p);
        i0 = find(p-sp<=0);
        if ~isempty(i0)
            threshold = p(max(i0));
        else
            threshold = -1.0;
        end
        
        %Significant p-values are smaller than threshold.
        sigPs = adj_mat <= threshold;
        Ctemp = zeros(n);
        Ctemp(sigPs)=1;
        net_coh(:,:,ii) = Ctemp+Ctemp';
    else
        net_coh(:,:,ii) = NaN(n,n);
    end
end

% Compute significant pvals for imaginary coherency
% net_imag_coh = zeros(n,n,num_nets);
% for ii = 1:num_nets
%     
%     if sum(sum(isfinite(pval_imag_coh(:,:,ii)))) >0
%         adj_mat = pval_imag_coh(:,:,ii);
%         p = adj_mat(isfinite(adj_mat));
%         p = sort(p);
%         i0 = find(p-sp<=0);
%         if ~isempty(i0)
%             threshold = p(max(i0));
%         else
%             threshold = -1.0;
%         end
%         
%         %Significant p-values are smaller than threshold.
%         sigPs = adj_mat <= threshold;
%         Ctemp = zeros(n);
%         Ctemp(sigPs)=1;
%         net_imag_coh(:,:,ii) = Ctemp+Ctemp';
%     else
%         net_imag_coh(:,:,ii) = NaN(n,n);
%     end
% end

% 6. Output/save everything

 model.net_coh = net_coh;
%  model.net_imag_coh = net_imag_coh;
%  model.pval_imag_coh = pval_imag_coh;
 model.pval_coh = pval_coh;


end
