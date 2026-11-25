function output = rppg_main(mode, inputFile, gtBpm)
% RPPG_MAIN  RGB 영상 기반 비접촉 심박 추정 (A/B/C/D + POS).
% 파일명을 rppg_main.m으로 저장하고 MATLAB Current Folder에 둔다.
% rppg_main('selftest')                 : 인공 RGB/시간 신호 검증
% rppg_main                             : 파일 선택, 수동 ROI, 결과 출력
% rppg_main('single','test.mp4',75)     : GT를 알고 있을 때 (선택)
% rppg_main('batch','experiments.csv')  : 영상 목록 일괄 평가
% Image Processing Toolbox 필요. Signal Processing/CV Toolbox 불필요.
% 실제 영상/환경에서 검증 전인 개발용 코드 (의료용 아님).
if nargin < 1 || isempty(mode), mode = 'single'; end
if nargin < 2, inputFile = ''; end
if nargin < 3, gtBpm = NaN; end
cfg = settings();
mode = lower(string(mode));
if mode == "selftest"
    output = selftest(cfg); return
end
assert(mode == "single" || mode == "batch", 'single, batch, selftest 중 선택하세요.');
need = {'VideoReader','drawrectangle','medfilt2','normxcorr2','imresize','rgb2gray'};
for k=1:numel(need)
    assert(~isempty(which(need{k})), '필요 함수가 없습니다: %s', need{k});
end
if isempty(inputFile)
    if mode == "single", filter = {'*.mp4;*.mov;*.avi','영상 파일'};
    else, filter = {'*.csv','실험 기록 CSV'}; end
    [name, folder] = uigetfile(filter);
    if isequal(name,0), output = []; return; end
    inputFile = fullfile(folder,name);
end
inputFile = char(inputFile);
if mode == "single"
    vr = VideoReader(inputFile);
    [~,id] = fileparts(inputFile);
    [pred,detail] = runVideo(inputFile,string(id),0,min(cfg.duration,vr.Duration),cfg);
    pred.gt_bpm = repmat(double(gtBpm),height(pred),1);
    pred.abs_error = abs(pred.predicted_bpm-pred.gt_bpm);
    disp(pred(:,{'method','gt_bpm','predicted_bpm','abs_error','quality','status','failure_reason'}));
    if ~isempty(detail), plotDetail(detail,pred); end
    output = pred;
else
    output = runBatch(inputFile,cfg);
end
end

function cfg = settings()
cfg.band = [0.7 3.0];         % Hz (42~180 BPM)
cfg.duration = 60;            % 권장 분석 시간 (초)
cfg.minDuration = 20;         % 예비 제안: 20초 미만 분석하지 않음
cfg.minValid = 0.90;          % 예비 제안: 공통 ROI 유효 비율
cfg.maxGap = 1.0;             % 예비 제안: 최대 허용 시간 공백 (초)
cfg.minBandFraction = 0.001; % 원신호 대역 에너지 최소 비율 (예비 제안)
cfg.minQuality = 0.15;        % 예비 제안: 대역 내 피크 에너지 비율
cfg.qualityHalfWidth = 0.10;  % Hz, 피크 주변 에너지 범위
cfg.order = 2;               % FFT 영역 Butterworth 형태 응답 차수
cfg.posWindow = 1.6;         % 초, POS 이동창
cfg.track = true;            % false: 고정 ROI 예비 실험만
cfg.trackMinCorr = 0.65;      % 예비 제안: 템플릿 상관계수
cfg.methods = ["A";"B";"C";"D";"POS";"POS_equal"];
end

function [pred,detail] = runVideo(file,id,startS,endS,cfg)
% 분석 실패도 삭제하지 않고 방법별 결과 행을 유지한다.
pred = emptyPred(id,cfg.methods); detail = [];
timer = tic; selectionSeconds=0;
try
    assert(isfinite(startS)&&isfinite(endS)&&startS>=0&&endS>startS,'잘못된 분석 구간');
    assert(endS-startS>=cfg.minDuration,'분석 시간이 너무 짧습니다.');
    [rgb,t,counts,roi,valid,medianRGB,selectionSeconds] = extractRGB(file,startS,endS,cfg);
    pred.roi_valid_rate(:) = mean(valid)*100;
    if any(valid), pred.mean_roi_pixels(:) = mean(sum(counts(valid,:),2)); end
    [tu,raw,med,ct,fs] = uniformSignals(t,rgb,medianRGB,counts,valid,startS,endS,cfg);
    [results,aux] = allMethods(tu,raw,med,ct,fs,cfg);
    for i=1:numel(results)
        pred.predicted_bpm(i) = results(i).bpm;
        pred.quality(i) = results(i).quality;
        pred.status(i) = results(i).status;
        pred.failure_reason(i) = results(i).reason;
        if i==4 || i==6, pred.valid_pos_rois(i)=sum([aux.roi_results.status]=="ok"); end
    end
    detail = struct('time',tu,'raw',raw,'med',med,'counts',ct,'fs',fs, ...
        'results',results,'aux',aux,'roi_positions',roi,'original_time',t,'valid',valid);
catch ME
    pred.failure_reason(:) = string(ME.message);
    fprintf('영상 실패: %s\n',ME.message);
end
pred.processing_s(:) = max(0,toc(timer)-selectionSeconds); % 모든 방법 공통 실행시간 (ROI 수동 선택 제외)
end

function T = emptyPred(id,methods)
n = numel(methods);
T = table(repmat(string(id),n,1),methods(:),nan(n,1),repmat("failed",n,1), ...
    repmat("",n,1),nan(n,1),nan(n,1),nan(n,1),nan(n,1),nan(n,1), ...
    'VariableNames',{'video_id','method','predicted_bpm','status','failure_reason', ...
    'quality','roi_valid_rate','mean_roi_pixels','processing_s','valid_pos_rois'});
end

function [raw,t,counts,positions,valid,med,selectionSeconds] = extractRGB(file,startS,endS,cfg)
v = VideoReader(file);
assert(endS<=v.Duration+0.15,'영상 길이가 요청 분석 구간보다 짧습니다.');
v.CurrentTime = startS;
assert(hasFrame(v),'영상에 분석할 프레임이 없습니다.');
firstTime=v.CurrentTime; first=readFrame(v);
[H,W,channels]=size(first); assert(channels==3,'RGB 영상이 필요합니다.');
% ROI 선택 좌표를 영상별로 저장하여 동일 영상에서 다시 사용한다.
selectionSeconds=0;
sidecar = sprintf('%s.roi_%0.3f.mat',file,startS);
if isfile(sidecar)
    s=load(sidecar,'rects','frameSize');
    assert(isequal(s.frameSize,[H W]),'저장 ROI와 영상 크기가 다릅니다. ROI 파일을 삭제하고 재선택하세요.');
    rects=s.rects;
else
    selectionTimer=tic;
    fig=figure('Name','ROI 선택: 이마, 왼쪽 볼, 오른쪽 볼');
    imshow(first); hold on; rects=zeros(3,4);
    names={'이마','왼쪽 볼','오른쪽 볼'};
    colors={'y','g','c'};
    for j=1:3
        title(sprintf('%s 피부만 사각형으로 선택하고 더블클릭',names{j}));
        h=drawrectangle('Color',colors{j}); wait(h);
        p=round(h.Position);
        x1=max(1,p(1)); y1=max(1,p(2));
        x2=min(W,p(1)+p(3)-1); y2=min(H,p(2)+p(4)-1);
        rects(j,:)=[x1 y1 x2-x1+1 y2-y1+1];
    end
    close(fig); selectionSeconds=toc(selectionTimer); frameSize=[H W];
    checkRects(rects,H,W);
    save(sidecar,'rects','frameSize');
end
checkRects(rects,H,W);
% 같은 얼굴 피부 위치를 유지하기 위한 경량 정규화 상관 추적.
% 원본 얼굴 패치의 평행이동만 추정한다. 회전/스케일 대응은 제한됨.
if cfg.track, tracker=initTracker(first,rects); else, tracker=[]; end
cap=max(100,ceil((endS-startS)*max(v.FrameRate,1))+20);
raw=nan(cap,3,3); med=raw; counts=zeros(cap,3); positions=nan(cap,4,3);
t=nan(cap,1); valid=false(cap,1); n=0;
frame=first; stamp=firstTime;
while stamp<endS
    if n==0 || stamp>t(n)
        n=n+1;
        if n>size(raw,1)
            raw(end+500,3,3)=NaN; med(end+500,3,3)=NaN;
            counts(end+500,3)=0; positions(end+500,4,3)=NaN;
            t(end+500,1)=NaN; valid(end+500,1)=false;
        end
        % 확장 배열의 빈 행이 0으로 채워져도 현재 행은 명시적으로 초기화.
        raw(n,:,:)=NaN; med(n,:,:)=NaN; counts(n,:)=0;
        positions(n,:,:)=NaN; valid(n)=false; t(n)=stamp;
        shift=[0 0]; good=true;
        if cfg.track && n>1
            [tracker,shift,good]=trackFrame(frame,tracker,cfg);
        end
        rr=rects; rr(:,1:2)=rr(:,1:2)+shift;
        good=good && all(rr(:,1)>=1 & rr(:,2)>=1 & ...
            rr(:,1)+rr(:,3)-1<=W & rr(:,2)+rr(:,4)-1<=H);
        if good
            for j=1:3
                x=rr(j,1); y=rr(j,2); w=rr(j,3); h=rr(j,4);
                patch=frame(y:y+h-1,x:x+w-1,:);
                % ROI 주변 1픽셀 포함: ROI 내부에서 full-frame 3x3 median과 동일.
                xa=max(1,x-1); ya=max(1,y-1); xb=min(W,x+w); yb=min(H,y+h);
                padded=frame(ya:yb,xa:xb,:);
                for c=1:3
                    q=double(patch(:,:,c)); raw(n,c,j)=mean(q(:));
                    f=medfilt2(padded(:,:,c),[3 3],'symmetric');
                    q=double(f(y-ya+1:y-ya+h,x-xa+1:x-xa+w));
                    med(n,c,j)=mean(q(:));
                end
                counts(n,j)=w*h; positions(n,:,j)=rr(j,:);
            end
            valid(n)=true;
        end
        if mod(n,300)==0, fprintf('  %d frames, ROI valid %.1f%%\n',n,100*mean(valid(1:n))); end
    end
    if ~hasFrame(v), break; end
    stamp=v.CurrentTime; frame=readFrame(v);
end
assert(n>1,'분석할 프레임이 부족합니다.');
raw=raw(1:n,:,:); med=med(1:n,:,:); counts=counts(1:n,:);
positions=positions(1:n,:,:); t=t(1:n); valid=valid(1:n);
end

function checkRects(r,H,W)
assert(isequal(size(r),[3 4]) && all(isfinite(r(:))) && all(r(:)==round(r(:))), 'ROI 좌표 오류');
assert(all(r(:,3)>=3 & r(:,4)>=3 & r(:,1)>=1 & r(:,2)>=1 & ...
    r(:,1)+r(:,3)-1<=W & r(:,2)+r(:,4)-1<=H),'ROI가 너무 작거나 화면 밖에 있습니다.');
for i=1:2
    for j=i+1:3
        overlap=min(r(i,1)+r(i,3)-1,r(j,1)+r(j,3)-1)>=max(r(i,1),r(j,1)) && ...
            min(r(i,2)+r(i,4)-1,r(j,2)+r(j,4)-1)>=max(r(i,2),r(j,2));
        assert(~overlap,'세 ROI가 서로 겹치면 안 됩니다.');
    end
end
end

function tr=initTracker(frame,r)
[H,W,~]=size(frame);
x1=min(r(:,1)); y1=min(r(:,2)); x2=max(r(:,1)+r(:,3)-1); y2=max(r(:,2)+r(:,4)-1);
pad=max(4,round(0.12*max(x2-x1,y2-y1)));
x1=max(1,x1-pad); y1=max(1,y1-pad); x2=min(W,x2+pad); y2=min(H,y2+pad);
tr.scale=min(1,160/max(x2-x1+1,y2-y1+1));
g=imresize(rgb2gray(frame),tr.scale);
% imresize의 픽셀 중심 좌표에 맞춰 변환한다.
x1s=max(1,round((x1-.5)*tr.scale+.5)); y1s=max(1,round((y1-.5)*tr.scale+.5));
x2s=min(size(g,2),round((x2-.5)*tr.scale+.5)); y2s=min(size(g,1),round((y2-.5)*tr.scale+.5));
tr.template=double(g(y1s:y2s,x1s:x2s));
assert(numel(tr.template)>=16 && std(tr.template(:))>0,'얼굴 추적용 템플릿에 정보가 부족합니다.');
tr.ref=[x1s y1s]; tr.last=tr.ref; tr.misses=0;
end

function [tr,shift,good]=trackFrame(frame,tr,cfg)
g=double(imresize(rgb2gray(frame),tr.scale)); [h,w]=size(tr.template);
rad=max(5,round(max(h,w)*.20))*min(4,1+tr.misses);
x1=max(1,tr.last(1)-rad); y1=max(1,tr.last(2)-rad);
x2=min(size(g,2),tr.last(1)+w-1+rad); y2=min(size(g,1),tr.last(2)+h-1+rad);
search=g(y1:y2,x1:x2); good=false; shift=[0 0];
if size(search,1)>=h && size(search,2)>=w && std(search(:))>0
    cc=normxcorr2(tr.template,search);
    % 패치 전체가 탐색 영역에 포함되는 상관값만 사용한다.
    cc=cc(h:size(search,1),w:size(search,2)); cc(~isfinite(cc))=-Inf;
    [peak,idx]=max(cc(:)); [yy,xx]=ind2sub(size(cc),idx);
    if peak>=cfg.trackMinCorr
        tr.last=[x1+xx-1,y1+yy-1];
        shift=round((tr.last-tr.ref)/tr.scale); good=true; tr.misses=0;
    end
end
if ~good, tr.misses=tr.misses+1; end
end

function [tu,raw,med,ct,fs]=uniformSignals(t,raw0,med0,ct0,valid,startS,endS,cfg)
assert(all(diff(t)>0),'프레임 시각이 단조 증가하지 않습니다.');
fs=1/median(diff(t)); assert(isfinite(fs)&&fs>2*cfg.band(2),'샘플링 주파수 부족');
valid=valid & all(isfinite(reshape(raw0,numel(t),[])),2) & ...
    all(isfinite(reshape(med0,numel(t),[])),2) & all(ct0>0,2);
assert(mean(valid)>=cfg.minValid,'공통 ROI 유효 비율 부족');
tv=t(valid); assert(numel(tv)>=2,'유효 프레임 부족');
assert(tv(1)-startS<=cfg.maxGap && endS-tv(end)<=cfg.maxGap,'분석 구간 시작/끝 ROI 결측');
assert(all(diff(tv)<=cfg.maxGap+1/fs),'연속 ROI/프레임 결측이 너무 깁니다.');
% 누락된 프레임까지 포함한 시간 커버리지 확인.
assert(numel(tv)/max(1,(endS-startS)*fs)>=cfg.minValid,'실제 시간 구간 내 유효 표본 부족');
N=floor((endS-startS)*fs+1e-6); assert(N>=cfg.minDuration*fs-1,'분석 표본 수 부족');
tu=startS+(0:N-1)'/fs;
% 작은 시작/끝 결측은 최근 유효값 유지, 내부의 짧은 결측은 선형 보간.
tq=min(max(tu,tv(1)),tv(end));
raw=reshape(interp1(tv,reshape(raw0(valid,:,:),numel(tv),9),tq,'linear'),N,3,3);
med=reshape(interp1(tv,reshape(med0(valid,:,:),numel(tv),9),tq,'linear'),N,3,3);
ct=interp1(tv,ct0(valid,:),tq,'linear');
end

function [res,aux]=allMethods(t,raw,med,counts,fs,cfg)
% A~C, 기본 POS는 픽셀 수를 반영한 공통 ROI RGB 평균 사용.
pooled=poolRGB(raw,counts); medPooled=poolRGB(med,counts);
res=repmat(blankResult(),6,1);
res(1)=estimateSignal(t,pooled(:,2),fs,cfg);
res(2)=estimateSignal(t,medPooled(:,2),fs,cfg);
den=sum(pooled,2); cn=nan(size(den)); ok=den>eps; cn(ok)=pooled(ok,2)./den(ok);
res(3)=estimateSignal(t,cn,fs,cfg);
res(5)=estimateSignal(t,posSignal(pooled,fs,cfg),fs,cfg);
roiRes=repmat(blankResult(),3,1);
for j=1:3, roiRes(j)=estimateSignal(t,posSignal(raw(:,:,j),fs,cfg),fs,cfg); end
ok=[roiRes.status]=="ok";
if any(ok)
    b=[roiRes(ok).bpm]; q=[roiRes(ok).quality];
    if sum(q)>0
        res(4)=fuseResults(roiRes(ok),q);
        res(6)=fuseResults(roiRes(ok),ones(size(q)));
    end
else
    res(4).reason="유효 POS ROI 없음"; res(6).reason=res(4).reason;
end
aux=struct('pooled',pooled,'roi_results',roiRes);
end

function x=poolRGB(raw,counts)
x=zeros(size(raw,1),3); den=sum(counts,2);
for j=1:3, x=x+raw(:,:,j).*counts(:,j); end
x=x./den;
end

function out=posSignal(rgb,fs,cfg)
% Wang et al., Algorithmic Principles of Remote PPG, 2017.
% 1.6초 이동창, 채널별 시간 평균 정규화, POS 투영, overlap-add.
N=size(rgb,1); L=max(3,round(cfg.posWindow*fs));
out=zeros(N,1); cover=zeros(N,1);
if N<L || any(~isfinite(rgb(:))), out(:)=NaN; return; end
for a=1:N-L+1
    idx=a:a+L-1; z=rgb(idx,:); mu=mean(z,1);
    if any(mu<=eps), continue; end
    z=z./mu;
    s1=z(:,2)-z(:,3); s2=z(:,2)+z(:,3)-2*z(:,1);
    d=std(s2); if d<=1e-12, continue; end
    h=s1+(std(s1)/d)*s2; h=h-mean(h);
    out(idx)=out(idx)+h; cover(idx)=cover(idx)+1;
end
% 표준 overlap-add; 초기/끝 창의 가중 변화는 품질 판정에서 검토.
if any(cover==0), out(:)=NaN; end
end

function r=blankResult()
r=struct('bpm',NaN,'quality',NaN,'status',"failed",'reason',"신호 부족", ...
    'time',[],'filtered',[],'freq',[],'power',[],'peak_hz',NaN);
end

function r=estimateSignal(t,x,fs,cfg)
r=blankResult(); x=double(x(:)); N=numel(x); r.time=t;
if N<4 || any(~isfinite(x)), r.reason="유효 신호 부족/NaN"; return; end
x=detrend(x,'linear');
if std(x)<=1e-10, r.reason="평탄 신호"; return; end
% 강의자료의 주파수 영역 필터링: 대칭 Butterworth형 HPF × LPF.
% 아날로그 IIR butter/bandpass와 같은 구현은 아니다.
p=min(N-1,round(3*fs)); xp=[flipud(x(2:p+1));x;flipud(x(end-p:end-1))];
M=numel(xp); k=(0:M-1)'; f=min(k,M-k)*fs/M;
HP=zeros(M,1); nz=f>0; HP(nz)=1./(1+(cfg.band(1)./f(nz)).^(2*cfg.order));
LP=1./(1+(f/cfg.band(2)).^(2*cfg.order));
y=real(ifft(fft(xp).*HP.*LP)); y=y(p+1:p+N); r.filtered=y;
if std(y)<=1e-10, r.reason="필터 후 평탄 신호"; return; end
% Hann 창으로 스펙트럼 누설 완화 (기본 MATLAB 수식).
win=.5-.5*cos(2*pi*(0:N-1)'/(N-1)); X=fft((y-mean(y)).*win);
f=(0:floor(N/2))'*fs/N; P=abs(X(1:numel(f))).^2;
r.freq=f; r.power=P;
band=find(f>=cfg.band(1)&f<=cfg.band(2));
if isempty(band) || sum(P(band))<=eps, r.reason="탐색 대역 에너지 없음"; return; end
% 대역 밖 신호만 있는 경우도 검출: 원신호 대역 내 에너지 비율.
Z=fft(x.*win); rawPower=abs(Z(1:numel(f))).^2;
if sum(rawPower(band))/max(sum(rawPower),eps)<cfg.minBandFraction
    r.reason="원신호의 심박 대역 에너지 부족"; return
end
[~,idx]=max(P(band)); k=band(idx); fp=f(k);
% 인접 bin의 log power 포물선 보간 (GT는 사용하지 않음).
if k>band(1)&&k<band(end)
    a=log(max(P(k-1),realmin)); b=log(max(P(k),realmin)); c=log(max(P(k+1),realmin));
    den=a-2*b+c;
    if den< -eps
        delta=max(-.5,min(.5,.5*(a-c)/den)); fp=fp+delta*fs/N;
    end
end
q=sum(P(band(abs(f(band)-fp)<=cfg.qualityHalfWidth)))/sum(P(band));
r.peak_hz=fp; r.quality=q;
if q<cfg.minQuality, r.reason="FFT 피크 품질 부족"; return; end
r.bpm=60*fp; r.status="ok"; r.reason="";
end

function r=fuseResults(rr,w)
w=w(:)/sum(w); b=[rr.bpm]'; q=[rr.quality]';
% BPM을 가중 평균한다. 그래프는 대표 ROI 파형/스펙트럼만 표시한다.
[~,idx]=max(w); r=rr(idx);
r.bpm=sum(w.*b); r.quality=sum(w.*q); r.peak_hz=NaN;
r.status="ok"; r.reason="";
end

function plotDetail(d,T)
figure('Name','RGB & rPPG results','Color','w');
tiledlayout(3,2,'TileSpacing','compact');
nexttile; plot(d.time,d.aux.pooled); legend('R','G','B'); xlabel('Time (s)'); ylabel('Mean intensity'); title('Original pooled RGB'); grid on
nexttile; hold on
for j=1:4
    r=d.results(j); if ~isempty(r.filtered), plot(r.time,r.filtered/max(std(r.filtered),eps),'DisplayName',char(T.method(j))); end
end
xlabel('Time (s)'); ylabel('Normalized amplitude'); title('Processed signals (D: representative ROI)'); legend('show'); grid on
nexttile; hold on
for j=1:5
    r=d.results(j); if ~isempty(r.power), plot(r.freq,r.power/max(max(r.power),eps),'DisplayName',char(T.method(j))); end
end
xlim([0 4]); xlabel('Hz'); ylabel('Normalized power'); title('FFT (D: representative ROI)'); legend('show'); grid on
nexttile; bar(categorical(T.method,T.method),T.predicted_bpm); hold on
if isfinite(T.gt_bpm(1)), yline(T.gt_bpm(1),'--','GT'); end
ylabel('BPM'); title('Estimated heart rate'); grid on
nexttile; bar(categorical(T.method,T.method),T.quality); ylim([0 1]); ylabel('Peak energy ratio'); title('Signal quality'); grid on
nexttile; plot(d.original_time,double(d.valid)); ylim([-.1 1.1]); xlabel('Time (s)'); title('ROI valid frames'); grid on
end

function result=runBatch(csv,cfg)
G=readtable(csv,'TextType','string');
required={'video_id','subject_id','distance_m','trial','video_file','start_s','end_s','gt_bpm'};
assert(all(ismember(required,G.Properties.VariableNames)),'CSV 열 이름이 기존 experiments_template.csv와 다릅니다.');
assert(height(G)>0,'CSV에 영상 기록이 없습니다.');
G.video_id=string(G.video_id); assert(numel(unique(G.video_id))==height(G),'video_id는 행별로 고유해야 합니다.');
G.start_s=str2double(string(G.start_s)); G.end_s=str2double(string(G.end_s));
G.gt_bpm=str2double(string(G.gt_bpm)); G.distance_m=str2double(string(G.distance_m));
folder=fileparts(csv); if isempty(folder), folder=pwd; end
outDir=fullfile(folder,'rppg_results'); if ~isfolder(outDir),mkdir(outDir); end
T=table();
for i=1:height(G)
    fprintf('\n[%d/%d] %s\n',i,height(G),G.video_id(i));
    file=char(G.video_file(i));
    if ~isfile(file),file=fullfile(folder,char(G.video_file(i)));end
    if ~isfile(file),file=fullfile(folder,'videos',char(G.video_file(i)));end
    [p,d]=runVideo(file,G.video_id(i),G.start_s(i),G.end_s(i),cfg);
    p.subject_id=repmat(string(G.subject_id(i)),height(p),1);
    p.distance_m=repmat(G.distance_m(i),height(p),1);
    p.trial=repmat(string(G.trial(i)),height(p),1);
    p.start_s=repmat(G.start_s(i),height(p),1); p.end_s=repmat(G.end_s(i),height(p),1);
    p.gt_bpm=repmat(G.gt_bpm(i),height(p),1);
    p.abs_error=abs(p.predicted_bpm-p.gt_bpm);
    if isempty(T),T=p;else,T=[T;p];end %#ok<AGROW>
    if ~isempty(d),save(fullfile(outDir,sprintf('trial_%03d.mat',i)),'d','p','cfg');end
    writetable(T,fullfile(outDir,'predictions.csv')); % 중간 결과 저장
end
S=summaryTable(T,cfg.methods,false); C=summaryTable(T,cfg.methods,true);
writetable(S,fullfile(outDir,'summary.csv')); writetable(C,fullfile(outDir,'common_summary.csv'));
disp(S(isnan(S.distance_m),:));
figure('Name','Distance performance','Color','w'); tiledlayout(1,3,'TileSpacing','compact');
fields={'MAE','RMSE','valid_rate'};
for j=1:3
    nexttile; hold on
    for m=cfg.methods'
        mask=S.method==m & isfinite(S.distance_m);
        plot(S.distance_m(mask),S.(fields{j})(mask),'-o','DisplayName',char(m));
    end
    xlabel('Distance (m)'); ylabel(fields{j},'Interpreter','none'); grid on; legend('show');
end
saveas(gcf,fullfile(outDir,'distance_summary.png'));
result=struct('predictions',T,'summary',S,'common_summary',C);
fprintf('결과 저장: %s\n',outDir);
end

function S=summaryTable(T,methods,commonOnly)
% GT 누락은 별도 집계, 유효율 분모는 전체 시도.
ids=unique(T.video_id); common=strings(0,1);
for i=1:numel(ids)
    z=T(T.video_id==ids(i)&ismember(T.method,methods(1:4)),:);
    if height(z)==4 && all(z.status=="ok" & isfinite(z.predicted_bpm) & isfinite(z.gt_bpm))
        common(end+1,1)=ids(i); %#ok<AGROW>
    end
end
S=table(); ds=[NaN;unique(T.distance_m(isfinite(T.distance_m)))];
for dist=ds'
    for m=methods'
        z=T(T.method==m & (isnan(dist)|T.distance_m==dist),:);
        if commonOnly, z=z(ismember(z.video_id,common),:);end
        n=height(z); valid=z.status=="ok"&isfinite(z.predicted_bpm); hasGT=isfinite(z.gt_bpm);
        paired=valid&hasGT; e=z.predicted_bpm(paired)-z.gt_bpm(paired);
        mae=NaN; rmse=NaN; rate=NaN; acc5=NaN;
        if any(paired),mae=mean(abs(e));rmse=sqrt(mean(e.^2));end
        if n>0,rate=100*sum(valid)/n;end
        if any(hasGT),acc5=100*sum(paired & abs(z.predicted_bpm-z.gt_bpm)<=5)/sum(hasGT);end
        row=table(m,dist,n,sum(valid),sum(paired),sum(~hasGT),mae,rmse,rate,acc5, ...
            'VariableNames',{'method','distance_m','n_total','n_valid','n_paired','n_gt_missing','MAE','RMSE','valid_rate','within5_rate'});
        if isempty(S),S=row;else,S=[S;row];end %#ok<AGROW>
    end
end
end

function out=selftest(cfg)
% 실제 영상이 없어도 핵심 주파수 분석/실패 처리/평가 지표를 검증한다.
fs=30; t=(0:1799)'/fs;
r=estimateSignal(t,sin(2*pi*1.25*t)+.4*sin(2*pi*5*t)+.5*cos(2*pi*.2*t),fs,cfg);
assert(r.status=="ok" && abs(r.bpm-75)<1,'75 BPM 인공 신호 테스트 실패');
flat=estimateSignal(t,ones(size(t)),fs,cfg); assert(flat.status=="failed",'평탄 신호 테스트 실패');
missing=estimateSignal(t,nan(size(t)),fs,cfg); assert(missing.status=="failed",'NaN 테스트 실패');
outside=estimateSignal(t,sin(2*pi*5*t),fs,cfg); assert(outside.status=="failed",'대역 외 신호 테스트 실패');
% 합성 RGB: 채널별 미세한 맥파 + 공통 조명 변화. 영상 자체는 아님.
raw=zeros(numel(t),3,3); pulse=sin(2*pi*1.25*t); illumination=1+.04*sin(2*pi*.2*t);
for j=1:3
    raw(:,:,j)=illumination.*([150 110 85]+pulse.*[.4 1.5 .2]);
end
ct=repmat([100 80 80],numel(t),1);
[res,~]=allMethods(t,raw,raw,ct,fs,cfg);
T=table(cfg.methods,[res.bpm]',[res.status]','VariableNames',{'method','BPM','status'});
disp(T); assert(all([res.bpm]>74 & [res.bpm]<76),'합성 RGB 테스트 실패');
% 평가 지표의 수치 검증: 2, -4 BPM 오차와 1회 실패.
P=emptyPred("S1","A"); P.status="ok"; P.predicted_bpm=77;
Q=emptyPred("S2","A"); Q.status="ok"; Q.predicted_bpm=76;
U=emptyPred("S3","A"); V=[P;Q;U]; V.gt_bpm=[75;80;70]; V.distance_m=ones(3,1);
S=summaryTable(V,cfg.methods,false); a=S(S.method=="A"&isnan(S.distance_m),:);
assert(abs(a.MAE-3)<1e-10 && abs(a.RMSE-sqrt(10))<1e-10 && abs(a.valid_rate-200/3)<1e-10,'평가 지표 테스트 실패');
fprintf('PASS: 75 BPM, 평탄/NaN/대역 밖, 합성 RGB, MAE/RMSE/유효 추정률\n');
out=T;
end
