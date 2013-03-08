classdef NeuralNetwork < handle
    properties (Constant)             
       TRAINING_MODE_SAMPLE_BY_SAMPLE = 1;
       TRAINING_MODE_BATCH            = 2;       

       TERMINATION_MODE_NONE      = 0;
       TERMINATION_MODE_EPOCHS    = 1;
       TERMINATION_MODE_ERROR     = 2;
       TERMINATION_MODE_EITHER    = 3;
       TERMINATION_MODE_BOTH      = 4;
       
       % The types of histories to remember. These can help analyze the
       % network, but may cost vast amounts of memory for large problems.
       % Using flags for flexibility.
       HISTORY_TYPE_NONE               = bin2dec('000000');
       HISTORY_TYPE_TRAINING_OUTPUTS   = bin2dec('000001');
       HISTORY_TYPE_TRAINING_ERRORS    = bin2dec('000010');
       HISTORY_TYPE_VALIDATION_OUTPUTS = bin2dec('000100');
       HISTORY_TYPE_VALIDATION_ERRORS  = bin2dec('001000');
       HISTORY_TYPE_WEIGHTS            = bin2dec('010000');
       HISTORY_TYPE_DERIVATIVES        = bin2dec('100000');       
       % Combination histories
       HISTORY_TYPE_TRAINING           = bin2dec('000011');
       HISTORY_TYPE_VALIDATION         = bin2dec('001100');
       HISTORY_TYPE_OUTPUTS            = bin2dec('000101');
       HISTORY_TYPE_ERRORS             = bin2dec('001010');
       HISTORY_TYPE_ALL                = bin2dec('111111');
    end

    properties
        trainingMode        = NeuralNetwork.TRAINING_MODE_SAMPLE_BY_SAMPLE;
        terminationMode     = NeuralNetwork.TERMINATION_MODE_EITHER;          
        maxEpochs           = 1000;
        maxError            = 0.001;
        alpha               = 0.1;
        histories           = NeuralNetwork.HISTORY_TYPE_ERRORS;
    end
    
    properties (SetAccess = private)
        % Full history of input and output data used for training or validation
        trainingData;
        validationData;
        
        % Number of inputs, outputs, and hidden neurons
        numInputs;
        numOutputs;       
        numHidden;
        numSamplesTraining;
        numSamplesValidation;
        
        % Three-dimensional matrices of outputs for training and validation.
        % 1 - Each is a sample (only 1 for batch mode)
        % 2 - Each is an epoch
        % 3 - Each is an output neuron        
        trainingOutputs;                
        
        % Two-dimensional matrices of errors for the above outputs
        % 1 - sample
        % 2 - epoch
        trainingErrors;
        
        % 1 - sample
        % 2 - output
        validationOutputs;
        
        % 1 - output error
        validationErrors;        
        
        % Five-dimensional matrices, first three dimensions are an instance
        % of a weight matrix, fourth dimension is the epoch index, fifth
        % dimension is the sample index (always 1 for batch mode).
        % 
        % These apply only to training, not validation. Weight matrices are 
        % described in further detail below.
        weightHistory;    
        derivativeHistory;    
        
        % Used to determine if it is ok to run validation
        hasTrained = 0;
        
        weights;
        finalTrainingError;
        finalValidationError;
                
        avgTrainingError; % of last epoch
        avgValidationError;
    end
    
    methods
        
        %%
        % train()   - Train this neural network using the back-propagation algorithm.
        %
        % Required parameters:
        %   data  - m by n matrix; m = samples, n = inputs and outputs
        %           (input columns and then output columns).
        %   numInputs - the number of inputs in the data table.      
        % Optional parameters:
        %   numHidden - Number of hidden neurons. Default is the mean number
        %             of inputs and output neurons rounded up (ceiling). 
        %   weights - The initial weights to use, given as a three dimensional
        %             matrix, x-y-z, where z always has the following layers:        
        %               1. Links between input and hidden neurons
        %               2. Hidden neuron biases
        %               3. Links between hidden and output neurons
        %               4. Output neuron biases        
        %             Each of these layers has its own sizes required to
        %             represent links using the x and y axes. For example,
        %             consider a neural network with 3 inputs, 10 hidden 
        %             neurons, and 2 outputs.
        %               Layer 1: x = 3, y = 10      (input, hidden)
        %               Layer 2: x = 10, y = 1      (hidden, none)
        %               Layer 3: x = 10, y = 2      (hidden, output)
        %               Layer 4: x = 2, y = 1       (output, none)
        %             The resultant matrix would be the largest of each
        %             dimension (10x10x4), while only 62 cells will be
        %             used. Memory usage could be optimized by ordering the 
        %             x and y values in each layer, but may not be worth the
        %             computational expense due to the frequent lookups
        %             needed.
        %             A better solution would be to designate positions for
        %             input, hidden, and output neurons. The method used
        %             here is to have the number of hidden neurons always
        %             be on the x axis; input and output neurons always
        %             reside on the y axis. For one dimensional layers, the
        %             number 1 takes the place of the type of neuron not being
        %             used. The resultant matrix is:
        %               Layer 1: x = 10, y = 3      (hidden, input)
        %               Layer 2: x = 10, y = 1      (hidden, none)
        %               Layer 3: x = 10, y = 2      (hidden, output)
        %               Layer 4: x = 1, y = 2       (none, output)
        %             10x3x4 or 120 is much closer to 62 than 400 was.
        %             There is no added computational expense because no 
        %             lookup is needed.
        function [weights outputError] = train(this, data, numInputs, ...
                numHidden, initialWeights)
            
            % ===================================
            % Validate input parameters/arguments
            % and set initial state.
            % ===================================                        
            
            % data
            if nargin < 2 || isempty(data) 
                error('train(): Cannot train without data.');
            end
            
            % numInputs
            if nargin < 3 || numInputs < 1
               error('train(): There must be at least one input.');
            end            
            
                % numOutputs
                numOutputs = size(data, 2) - numInputs;
                if numOutputs < 1
                   error('train(): There must be at least one output.'); 
                end

                % numSamples
                numSamples = size(data, 1);
                if numSamples < 1
                    error('train(): There must be at least one sample.');
                end
                
                % inputs
                inputs = data(:, 1:numInputs);
                
                % outputs
                outputs = data(:, (numInputs + 1):(numInputs + numOutputs));
            
            % numHidden
            if nargin >= 4                
                if numHidden < 1
                    error('train(): There must be at least one hidden neuron.');                 
                end
            else
                % Default number of hidden neurons is the average number of 
                % inputs and outputs, rounded up.
                numHidden = ceil(mean([numInputs numOutputs]));
            end
            
            % initialWeights
            weights = this.makeWeightMatrix(numInputs, numHidden, numOutputs);  
            if nargin >= 5 
                if size(initialWeights) ~= size(weights)
                    error('train(): Size of weight matrix should be %s.', size(weights));
                else
                    weights = initialWeights;
                end               
            end
                       
            % 
            % Reset information about previous training/validation attempts
            % 
            
            this.trainingData         = data;
            this.validationData       = null(1);
            
            this.numInputs            = numInputs;
            this.numOutputs           = numOutputs;
            this.numHidden            = numHidden;    
            this.numSamplesTraining   = numSamples;
                        
            this.trainingOutputs      = null(1);
            this.trainingErrors       = null(1);
            
            this.validationOutputs    = null(1);
            this.validationErrors     = null(1);
            
            this.weightHistory        = zeros(size(weights));
            this.derivativeHistory    = zeros(size(weights));
            
            this.weights              = weights;
            this.finalTrainingError   = Inf;
            this.finalValidationError = Inf;
                        
            this.hasTrained           = 0;
            
            
            % ===========================================================
            % Train using the specified mode and limits of this instance.
            % ===========================================================
            
            iEpoch = 1;
            outputError = Inf;   
            switch this.trainingMode
                case NeuralNetwork.TRAINING_MODE_SAMPLE_BY_SAMPLE
                    while ~(this.isComplete(iEpoch, outputError))
                        for jSample = 1 : numSamples
                            sampleInputs = inputs(jSample, :);
                            sampleOutputs = outputs(jSample, :);                                                                                    
                            
                            %
                            % Main part of loop 
                            %

                            % Update the weight values (except the very
                            % first occurance, because initial weights have
                            % already been given. This could be done at the
                            % end of the loop but then the weights returned
                            % will not be the most recent weights used.
                            if ~(iEpoch == 1 && jSample == 1)
                                weights = this.updateWeights(weights, derivatives, numInputs, numOutputs);
                            end
                            
                            % Calculate ynn
                            [computedOutputs z] = this.computeOutputs(sampleInputs, weights, numOutputs);
                            
                            % Calculate the error of the outputs in this sample
                            outputError = this.computeError(computedOutputs, sampleOutputs);                            
                                                                                    
                            % Compute the error derivatives for each weight
                            derivatives = this.computeDerivatives(computedOutputs, ...
                                sampleInputs, sampleOutputs, weights, z);
                            
                            
                            %
                            % Record desired information
                            %
                            
                            % Computed outputs
                            if bitand(this.histories, NeuralNetwork.HISTORY_TYPE_TRAINING_OUTPUTS)
                                this.trainingOutputs(jSample, iEpoch, :) = computedOutputs;                                
                            end
                            
                            % Sample errors
                            if bitand(this.histories, NeuralNetwork.HISTORY_TYPE_TRAINING_ERRORS)                                
                                this.trainingErrors(jSample, iEpoch) = outputError;                                
                            end
                            
                            % Weights
                            if bitand(this.histories, NeuralNetwork.HISTORY_TYPE_WEIGHTS)
                                this.weightHistory(:, :, :, iEpoch, jSample) = weights;
                            end
                            
                            % Derivatives
                            if bitand(this.histories, NeuralNetwork.HISTORY_TYPE_DERIVATIVES)
                                this.derivativeHistory(:, :, :, iEpoch, jSample) = derivatives;
                            end
                        end
                        iEpoch = iEpoch + 1;
                    end       
                case NeuralNetwork.TRAINING_MODE_BATCH
                    error('train(): Batch mode is not implemented yet.');     
            end

            this.weights = weights;
            this.finalTrainingError = outputError;   
            this.avgTrainingError = mean(this.trainingErrors(:, iEpoch - 1));
            this.hasTrained = 1;
        end
        
        %%
        function outputError = validate(this, data)
            if ~(this.hasTrained)
               error('validate(): Cannot validate without training first.'); 
            end
            
            if nargin < 2 || isempty(data)
                error('validate(): Cannot validate without data.');
            end
            
            if size(data, 2) ~= size(this.trainingData, 2)
               error('validate(): Validation data must have the same number of inputs/outputs as the training data.');
            end
                       
            inputs = data(:, 1:this.numInputs);
            outputs = data(:, (this.numInputs + 1):(this.numInputs + this.numOutputs));
            this.numSamplesValidation = size(data, 1);

            outputError = Inf;   
            switch this.trainingMode
                case NeuralNetwork.TRAINING_MODE_SAMPLE_BY_SAMPLE
                    for iSample = 1 : this.numSamplesValidation
                        sampleInputs = inputs(iSample, :);
                        sampleOutputs = outputs(iSample, :);                 
                        
                        computedOutputs = this.computeOutputs(sampleInputs, this.weights, this.numOutputs);
                        outputError = this.computeError(computedOutputs, sampleOutputs); 
                        
                        if bitand(this.histories, NeuralNetwork.HISTORY_TYPE_VALIDATION_OUTPUTS)
                            this.validationOutputs(iSample, :) = computedOutputs;                                
                        end
                        if bitand(this.histories, NeuralNetwork.HISTORY_TYPE_VALIDATION_ERRORS)                                
                            this.validationErrors(iSample) = outputError;
                        end
                    end
                case NeuralNetwork.TRAINING_MODE_BATCH
                    error('validate(): Batch mode is not implemented yet.');
            end
            
            this.finalValidationError = outputError;
            outputError = mean(this.validationErrors);
        end
        
        %%
        function plot(this)            
            figure;
            switch this.trainingMode
                case NeuralNetwork.TRAINING_MODE_SAMPLE_BY_SAMPLE                       
                    subplot(2, 1, 1), errorbar(mean(this.trainingErrors, 1), std(this.trainingErrors, 0, 1), ':');
                    hold on                    
                    plot(mean(this.trainingErrors, 1), 'r');     
                    hold off
                    subplot(2, 1, 2), plot(this.validationErrors);
                    hold on
                    avg = mean(this.validationErrors);
                    y(1:this.numSamplesValidation) = avg;
                    plot(y, 'r');
                    hold off

                case NeuralNetwork.TRAINING_MODE_BATCH
                    error('plot(): Batch mode is not implemented yet.');
            end                            
        end
    end
    
    %%
    methods (Access = private)
        
        %%
        % Make a matrix for the initial weights of a neural network with
        % the given amount of neurons at each level. The weight matrix has
        % three dimensions/arguments:
        %   1st: Hidden neuron index, or '1' if there isnt any (output biases)
        %   2nd: Input or output neuron index, or '1' if there isn't any (hidden biases)
        %   3rd: "Layer" or group which this type of weight belongs
        %        (input-hidden, hidden bias, hidden-output, output bias).
        %
        %   e.g.    weights(hidden, input/output, group);
        %
        function weights = makeWeightMatrix(this, numInputs, numHidden, numOutputs)
            x = numHidden;
            y = max(numInputs, numOutputs);
            z = 4;
            
            weights = zeros(x, y, z);
            
            for jHidden = 1 : numHidden
               
                % Input-Hidden link default weights (layer 1)
                for iInput = 1 : numInputs
                    weights(jHidden, iInput, 1) = (-1)^(iInput + jHidden);
                end

                % Hidden bias weights (layer 2)
                weights(jHidden, 1, 2) = 1;
            end
            
            for jHidden = 1 : numHidden
               for kOutput = 1 : numOutputs
                    
                   % Hidden-Output link default weights (layer 3)
                    weights(jHidden, kOutput, 3) = (-1)^(jHidden + kOutput);
                    
                    % Output bias weights (layer 4)
                    if jHidden == 1
                        weights(1, kOutput, 4) = 1;
                    end                    
               end               
            end           
        end
         
        %%
        function result = isComplete(this, iEpoch, currentError)
            switch this.terminationMode
                case NeuralNetwork.TERMINATION_MODE_NONE
                    result = 0;
                case NeuralNetwork.TERMINATION_MODE_EPOCHS
                    result = iEpoch > this.maxEpochs;
                case NeuralNetwork.TERMINATION_MODE_ERROR
                    result = currentError < this.maxError;
                case NeuralNetwork.TERMINATION_MODE_EITHER
                    result = iEpoch > this.maxEpochs ...
                             || currentError < this.maxError;
                case NeuralNetwork.TERMINATION_MODE_BOTH
                    result = iEpoch > this.maxEpochs ...
                             && currentError < this.maxError;
            end
        end
        
        %% Compute output(s) of one sample
        function [y z] = computeOutputs(this, inputs, weights, numOutputs)
            numInputs = size(inputs, 2);
            numHidden = size(weights, 1);         
                      
            gamma = zeros(numHidden, 1);
            z     = zeros(numHidden, 1);  
            y     = zeros(numOutputs, 1);
            
            for kOutput = 1 : numOutputs
                
                % Initial output value is it's bias                
                y(kOutput) = weights(1, kOutput, 4);
                
                for jHidden = 1 : numHidden                    
                    
                    % Initial gamma value is the hidden neuron's bias
                    gamma(jHidden) = weights(jHidden, 1, 2);
                    
                    % Add each term together for gamma
                    for iInput = 1 : numInputs                        
                        gamma(jHidden) = gamma(jHidden) + weights(jHidden, iInput, 1) * inputs(iInput);
                    end
                    
                    % Calculate z for this hidden neuron
                    z(jHidden) = 1 / (1 + exp(-gamma(jHidden)));
                    
                    % Add this hidden neuron's effect on the current output
                    y(kOutput) = y(kOutput) + weights(jHidden, kOutput, 3) * z(jHidden);
                end          
            end
        end
        
        %% Compute the error of one sample
        function err = computeError(this, y, outputs)
            err = 0;
            for iOutput = 1 : size(outputs, 2)
               err = err + .5 * (y(iOutput) - outputs(iOutput))^2;
            end
        end
        
        %%
        % Derivative of the error with respect to each weight. The
        % derivatives matrix has the same format as the weight matrix (i.e.
        % four layers/groups).
        function derivatives = computeDerivatives(this, y, inputs, ...
                outputs, weights, z)
            
            numInputs = size(inputs, 2);
            numHidden = size(weights, 1);
            numOutputs = size(outputs, 2);
            
            derivatives = zeros(size(weights));
            
            for kOutput = 1 : numOutputs
                
                % Derivative with respect to the output
                % ynn - ytable
                derivatives(1, kOutput, 4) = y(kOutput) - outputs(kOutput);
                
                for jHidden = 1 : numHidden;
                    
                    % Derivative with respect to hidden-output link weights
                    % dE/dy * zj
                    derivatives(jHidden, kOutput, 3) = derivatives(1, kOutput, 4) * z(jHidden);
                    
                    % Derivative with respect to hidden neuron biases
                    % sum(dE/dy * (hidden-output link derivative) * zj * (1 - zj))
                    derivatives(jHidden, 1, 2) = derivatives(jHidden, 1, 2) ...
                        + derivatives(1, kOutput, 4) ...
                        * derivatives(jHidden, kOutput, 3) ...
                        * z(jHidden) * (1 - z(jHidden));
                    
                    % Derivative with respect to input-hidden link weights
                    % sum(dE/dy * (hidden-output link derivative) * zj * (1 - zj) * xi)
                    for iInput = 1 : numInputs
                        derivatives(jHidden, iInput, 1) = derivatives(jHidden, iInput, 1) ...
                            + derivatives(1, kOutput, 4) ...
                            * derivatives(jHidden, kOutput, 3) ...
                            * z(jHidden) * (1 - z(jHidden)) * inputs(iInput);
                    end
                end
            end
        end
        
        %%
        function weights = updateWeights(this, weights, derivatives, numInputs, numOutputs)            
            numHidden = size(weights, 1);            
                 
            % Update input-hidden link weights
            for iInput = 1 : numInputs                
                for jHidden = 1 : numHidden
                    weights(jHidden, iInput, 1) = weights(jHidden, iInput, 1) ...
                        - derivatives(jHidden, iInput, 1) * this.alpha;
                end
            end
            
            
            for jHidden = 1 : numHidden
                
                % Update hidden neuron biases
                weights(jHidden, 1, 2) = weights(jHidden, 1, 2) ...
                    - derivatives(jHidden, 1, 2) * this.alpha;

                % Update hidden-output link weights
                for kOutput = 1 : numOutputs                        
                    weights(jHidden, kOutput, 3) = weights(jHidden, kOutput, 3) ...
                        - derivatives(jHidden, kOutput, 3) * this.alpha;                    
                end
            end
            
             % Update output neuron biases
            for kOutput = 1 : numOutputs               
                weights(1, kOutput, 4) = weights(1, kOutput, 4) ...
                    - derivatives(1, kOutput, 4) * this.alpha;  
            end
            
        end
    end
end