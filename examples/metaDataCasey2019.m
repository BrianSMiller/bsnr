function data = metaDataCasey2018
% data = metaDataCasey2016;
% Load the long-term spectral average from AAD whale recorder deployed on
% Casey Resupply route from Dec 2015 - 2016

startDate = datenum([2018 12 23 00 00 00]);
endDate = datenum([2019 12 13 00 00 00]); % Recorder stopped before recovery

data.site = 'Casey';
data.code = 'Casey2019';
data.hydroSensitivity_dB = -165.9; % dB re 1 V/uPa
frontEndSerial = 5;
[data.frontEndGain_dB, data.frontEndFreq_Hz] = loadfrontEndTF(frontEndSerial);
% data.frontEndGain_dB = [9.282379	15.54816	18.46558	19.5813	19.95298	20.01221	20.02684	20.03419	20.04422	20.03939	12.26664	-23.9081	-60.1025]; % dB?
% data.frontEndFreq_Hz = [	2	5	10	20	50	100	200	500	1000	2000	5000	10000	20000];
data.adPeakVolt = 1.5; % 16 bits encoded between 0 and 3V, so 1.5 Volts peak
data.sampleRate = 12000;
data.latitude = -63.80645; % Actual deployment 63 47.730 S, 111 47.225E
data.longitude =  111.75685;
data.depth = 2700.0; % approximate
data.startDate = startDate;
data.endDate = endDate;
data.ltsaFile = fullfile(ltsaFolder, 'casey2019_3600s_1Hz.ltsa.mat');
data.wavFolder = fullfile(marWavBase,'Casey2019\');