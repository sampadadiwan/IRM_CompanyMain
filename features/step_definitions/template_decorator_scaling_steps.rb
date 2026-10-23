Given('a decorated value of {string}') do |value|
  @scaled_decorator = TemplateDecorator.decorate(OpenStruct.new(amount: value.to_d))
end

Then('dividing it by 10^{int} gives {string}') do |power, expected|
  expect(@scaled_decorator.public_send(:"div_#{power}_amount")).to eq(expected.to_d)
end

Then('multiplying it by 10^{int} gives {string}') do |power, expected|
  expect(@scaled_decorator.public_send(:"mult_#{power}_amount")).to eq(expected.to_d)
end
