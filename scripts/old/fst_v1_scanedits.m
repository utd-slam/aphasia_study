%% fst_v1.m
% Script to run FST for aphasia study. Ported from isss_multiband_v7
% Author - Matt Heard

% CHANGELOG (DD/MM/YY)
% 07/08/17  Started changelog. -- MH
% 07/08/17  Found error in "prepare timing keys" that overwrote eventStartKey
%   and stimStartKey every time code completed a run. Fixed! -- MH
% 09/08/17  Preparing for testing, making sure code looks pretty. -- MH
% 03/01/18  Updated to run subjects 11 through 14 (one tiny change on line
%   160)
% 05/03/18  Updated to run FST for aphasia study

% function fst_v1
%% Startup
sca; DisableKeysForKbCheck([]); KbQueueStop;
Screen('Preference','VisualDebugLevel', 0);

try
    PsychPortAudio('Close'); 
catch
    disp('PPA already closed')
end
InitializePsychSound

clearvars; clc; 
codeStart = GetSecs(); 
AudioDevice = PsychPortAudio('GetDevices', 3); 

%% Parameters
prompt = {...
    'Subject number (####YL)', ...
    'Which session (1 - pre/2 - post)', ...
    'First run (1-4, enter 0 for mock)', ... 
    'Last run (1-4, enter 0 for mock)', ... 
    'RTBox connected (0/1):', ...
    'Script test (type "test" or leave blank)', ... 
    }; 
dlg_ans = inputdlg(prompt); 

subj.num  = dlg_ans{1};
subj.whichSess = dlg_ans{2}; 
subj.firstRun = str2double(dlg_ans{3}); 
subj.lastRun  = str2double(dlg_ans{4}); 
ConnectedToRTBox   = str2double(dlg_ans{5}); 
scriptTest = dlg_ans{6}; 

% Mock exception
if subj.firstRun == 0
    Mock = 1; 
    t.runs = 1;
    subj.firstRun = 1; 
    subj.lastRun = 1;
else
    Mock = 0;
end

% Test flag
if strcmp(scriptTest, 'test')
    Test = 1;
else
    Test = 0;
end

Screen('Preference', 'SkipSyncTests', Test);

% Scan type
scan.type   = 'Hybrid';
scan.TR     = 1.000; 
scan.epiNum = 10; 

% Number of stimuli -- Needs work
numSentences = 48; % 48 different sentence structures in stim folder
numSpeechSounds = numSentences*4;
numStim = numSpeechSounds+6; % Four permutations per sentence, six noise

% Timing
t.runs = length(subj.firstRun:subj.lastRun); % Maximum 4
t.events = 18; 

t.presTime   = 4.000;  % 4 seconds
t.epiTime    = 10.000; % 10 seconds
t.eventTime  = t.presTime + t.epiTime;

t.runDuration = t.epiTime + ...   % After first pulse
    t.eventTime * t.events + ...  % Each event
    t.eventTime;                  % After last acquisition

t.rxnWindow = 3.000;  % 3 seconds
t.jitWindow = 0.700;  % 0.7 second, see notes below. Likely will change?
    % For this experiment, the 0.9 seconds of the silent window will not
    % have stimuli presented. To code for this, I add an additional 0.9 s
    % to the jitterKey. So, the jitter window ranges from 0.9 s to 1.6 s.
    
%% Paths
cd ..
dir_exp = pwd; 

dir_stim    = fullfile(dir_exp, 'stim', 'fst');
dir_scripts = fullfile(dir_exp, 'scripts');
dir_results = fullfile(dir_exp, 'results', subj.num);
dir_funcs   = fullfile(dir_scripts, 'functions');

cd ..

% Instructions = 'instructions_lang.txt';

%% Preallocating timing variables
maxNumRuns = 4; 

AbsEvStart    = NaN(t.events, maxNumRuns); 
AbsStimStart  = NaN(t.events, maxNumRuns); 
AbsStimEnd    = NaN(t.events, maxNumRuns); 
AbsRxnEnd     = NaN(t.events, maxNumRuns); 
AbsEvEnd      = NaN(t.events, maxNumRuns); 
ansKey        = NaN(t.events, maxNumRuns); 
eventEnd      = NaN(t.events, maxNumRuns); 
eventEndKey   = NaN(t.events, maxNumRuns); 
eventStart    = NaN(t.events, maxNumRuns);
eventStartKey = NaN(t.events, maxNumRuns); 
jitterKey     = NaN(t.events, maxNumRuns); 
recStart      = NaN(t.events, maxNumRuns);
recStartKey   = NaN(t.events, maxNumRuns);
stimDuration  = NaN(t.events, maxNumRuns); 
stimEnd       = NaN(t.events, maxNumRuns); 
stimEndKey    = NaN(t.events, maxNumRuns);
stimStart     = NaN(t.events, maxNumRuns); 
stimStartKey  = NaN(t.events, maxNumRuns); 

firstPulse = NaN(1, maxNumRuns); 
runEnd     = NaN(1, maxNumRuns); 

respTime = cell(t.events, maxNumRuns); 
respKey  = cell(t.events, maxNumRuns); 

%% File names
filetag = [subj.num '_']; 
ResultsXls = fullfile(dir_results, [subj.num '_fst_results.xlsx']); 
Variables  = fullfile(dir_results, [subj.num '_fst_variables.mat']); 

%% Load stim
% Stimuli
cd(dir_stim) 
files = dir('*.wav'); 

% TEST - Did all files load correctly?
if length(files) ~= numStim
    error('Check the number of stimuli you listed or number of files in stim dir!')
end

ad = cell(1, length(files));
fs = cell(1, length(files));

for ii = 1:length(files)
    [adTemp, fsTemp] = audioread(files(ii).name);
    ad{ii}    = [adTemp'; adTemp']; % Convert mono to stereo
    fs{ii} = fsTemp;
    if ii ~= 1 % Check samplingrate is same across files 
        if fs{ii} ~= fs{ii-1}
            error('Your sampling rates are not all the same. Stimuli will not play correctly.')
        end
    end
end
fs = fs{1}; 

audinfo(length(ad)) = audioinfo(files(end).name); % Preallocate struct
for ii = 1:length(files)
    audinfo(ii) = audioinfo(files(ii).name); 
end

rawStimDur = nan(1, length(ad));
for ii = 1:length(ad)
    rawStimDur(ii) = audinfo(ii).Duration; 
end

%% Make keys
% jitterKey -- How much is the silent period jittered by?
for ii = subj.firstRun:subj.lastRun
    jitterKey(:, ii) = 0.9 + rand(t.events, 1); % Add 0.9 because stimuli are short-ish
end

% speechkey -- Which speech stimuli should we use this run?
% eventkey -- In what order will stimuli be presented?
randomstim   = NaN(16, maxNumRuns); % There are 16 sentences to present

if Mock
    sentence = repmat([129:4:192]', 1, 4); %#ok<NBRAK>
    noise = repmat([197; 198], 1, 4);
else
    sentence = [1:4:64; 65:4:128; 1:4:64; 65:4:128]';
    noise = repmat([193, 195; 194, 196], 1, 2);
end

for ii = subj.firstRun:subj.lastRun
    randomstim(:, ii) = Shuffle(vertcat( ... 
        0 * ones(4, 1), ...  
        1 * ones(4, 1), ...  
        2 * ones(4, 1), ... 
        3 * ones(4, 1) ... 
        ));  
end

speechKey = sentence + randomstim;
eventKey  = Shuffle(vertcat(speechKey, noise)); 

% anskey -- What should have subjects responded with?
for ii = 1:t.events
    for j = subj.firstRun:subj.lastRun
        if     eventKey(ii, j) > numSpeechSounds % Noise
            ansKey(ii, j) = 3; 
        elseif mod(eventKey(ii, j), 2) == 0      % Male
            ansKey(ii, j) = 2; 
        elseif mod(eventKey(ii, j), 2) == 1      % Female
            ansKey(ii, j) = 1; 
        end
    end
end

%% Check counterbalance
% Do we want to use the same stimuli in the pre- and post-training scan
% sessions?
cd(dir_funcs)
stimulicheck_fst(numSpeechSounds, eventKey); 

for ii = subj.firstRun:subj.lastRun
    stimDuration(:, ii) = rawStimDur(eventKey(:,ii))'; 
end

%% Open PTB, RTBox, PsychPortAudio
[wPtr, rect] = Screen('OpenWindow', 0, 185);
DrawFormattedText(wPtr, 'Please wait, preparing experiment...');
Screen('Flip', wPtr);

centerX = rect(3)/2;
centerY = rect(4)/2;
crossCoords = [-30, 30, 0, 0; 0, 0, -30, 30]; 
HideCursor(); 
RTBox('fake', ~ConnectedToRTBox);

pahandle = PsychPortAudio('Open', [], [], [], fs);

%% Prepare test
try
    for blk = subj.firstRun:subj.lastRun

        DrawFormattedText(wPtr, 'Please wait, preparing run...');
        Screen('Flip', wPtr); 

        % Prepare timing keys
        eventStartKey(:, blk) = t.epiTime + [0:t.eventTime:((t.events-1)*t.eventTime)]'; %#ok<NBRAK>
        stimStartKey(:, blk)  = eventStartKey(:, blk) + jitterKey(:, blk); 

%         if Training
%             stimEndKey = stimStartKey + rawStimDur(eventKey)';
%         else
            stimEndKey(:, blk) = stimStartKey(:, blk) + rawStimDur(eventKey(:,blk))';
%         end

        rxnEndKey   = stimEndKey + t.rxnWindow; 
        eventEndKey = eventStartKey + t.eventTime;

        % Display instructions
%         if Training
%             cd(dir_funcs)
%             DisplayInstructions_bkfw_rtbox(Instructions, wPtr, RTBoxLoc); 
%             cd(dir_exp)
%         end


        % Wait for first pulse
        DrawFormattedText(wPtr, ['Waiting for first pulse. Block ', num2str(blk)]); 
        Screen('Flip', wPtr); 
        
        RTBox('Clear'); 
        RTBox('UntilTimeout', 1);
        firstPulse(blk) = RTBox('WaitTR'); 

        % Draw onto screen after recieving first pulse
        Screen('DrawLines', wPtr, crossCoords, 2, 0, [centerX, centerY]);
        Screen('Flip', wPtr); 

        % Generate absolute time keys
        AbsEvStart(:, blk)   = firstPulse(blk) + eventStartKey(:,blk); 
        AbsStimStart(:, blk) = firstPulse(blk) + stimStartKey(:,blk); 
        AbsStimEnd(:, blk)   = firstPulse(blk) + stimEndKey(:,blk); 
        AbsRxnEnd(:, blk)    = firstPulse(blk) + rxnEndKey(:,blk); 
        AbsEvEnd(:, blk)     = firstPulse(blk) + eventEndKey(:,blk); 

        WaitTill(firstPulse(blk) + t.epiTime); 

        %% Present audio stimuli
        for evt = 1:t.events
            eventStart(evt, blk) = GetSecs(); 

            PsychPortAudio('FillBuffer', pahandle, ad{eventKey(evt, blk)});
            WaitTill(AbsStimStart(evt, blk)-0.1); 

            stimStart(evt, blk) = PsychPortAudio('Start', pahandle, 1, AbsStimStart(evt, blk), 1);
            WaitTill(AbsStimEnd(evt, blk)); 
            stimEnd(evt, blk) = GetSecs; 
            RTBox('Clear'); 

            [respTime{evt, blk}, respKey{evt, blk}] = RTBox(AbsRxnEnd(evt, blk)); 

            WaitTill(AbsEvEnd(evt, blk));    
            eventEnd(evt, blk) = GetSecs(); 
        end

        WaitSecs(t.eventTime); 
        runEnd(blk) = GetSecs(); 

        if blk ~= subj.lastRun
            DrawFormattedText(wPtr, 'End of run. Great job!', 'center', 'center'); 
            Screen('Flip', wPtr); 
            WaitTill(GetSecs() + 6);
        end 
                    
    end
    
catch err
    sca; 
    runEnd(blk) = GetSecs();  %#ok<NASGU>
    cd(dir_funcs)
    disp('Dumping data...')
    OutputData_fst
    cd(dir_scripts)
    PsychPortAudio('Close'); 
    disp('Done!')
    rethrow(err)
end

%% Closing down
Screen('CloseAll');
PsychPortAudio('Close'); 
DisableKeysForKbCheck([]); 

%% Save data
cd(dir_funcs)
disp('Please wait, saving data...')
OutputData_fst
disp('All done!')
cd(dir_scripts)

% end
