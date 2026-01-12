class FitnessKitSlugConstraint
  def self.matches?(request)
    slug = request.path_parameters[:slug]
    return false if slug.blank?

    # Check if a PromiseFitnessKit with this slug exists
    PromiseFitnessKit.exists?(slug: slug)
  end
end
