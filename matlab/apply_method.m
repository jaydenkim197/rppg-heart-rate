function method_signal = apply_method(rgb_data, method, settings)
%APPLY_METHOD 공통 RGB 데이터로 방법 A~D의 시간 신호를 만들 함수 틀.
% method는 'A', 'B', 'C', 'D' 중 하나다.
% 출력은 time_s, values, labels, method를 갖는 구조체다.
% B에는 extract_rgb에서 공간 필터를 적용해 얻은 RGB를 사용한다.

error('rppg:NotImplemented', ...
    'apply_method의 Green, 색상 정규화, POS 신호 생성을 구현해야 합니다.');
end
