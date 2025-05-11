class EoiCreate < EoiAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
end
