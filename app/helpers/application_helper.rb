module ApplicationHelper
  def contribution_badge(count)
    case count
    when 100..Float::INFINITY
      { name: "レジェンド", icon: "👑", color: "#b00020" }
    when 30..99
      { name: "ゴールド", icon: "🥇", color: "#d4af37" }
    when 10..29
      { name: "シルバー", icon: "🥈", color: "#6f42c1" }
    when 5..9
      { name: "サポーター", icon: "🥉", color: "#0d6efd" }
    when 1..4
      { name: "ルーキー", icon: "🌱", color: "#198754" }
    else
      nil
    end
  end
end
